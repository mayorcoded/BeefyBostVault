// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { BalancerV2Vault } from "./exchanges/BalancerV2.sol";
import { IBeefyBoost, IBeefyVault } from "./interfaces/IBeefy.sol";
import { FixedPointMathLib as Math } from "solmate/src/utils/FixedPointMathLib.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

contract BeefyBoostStrategy is BalancerV2Vault, OwnableUpgradeable, PausableUpgradeable, ERC4626Upgradeable {
    error ZeroShares();
    error ZeroMooTokens();
    error InvalidAddress();

    event Harvest(
        address indexed recipient,
        address indexed rewardToken,
        uint256 indexed rewardEarned
    );

    using Math for uint256;

    uint256 public totalStake;
    IBeefyVault public beefyVault;
    IBeefyBoost public beefyBoost;

    function initialize(
        ERC20Upgradeable lpToken,
        IBeefyVault _beefyVault,
        IBeefyBoost _beefyBoost
    ) initializer public {
        if(address (0) == address (_beefyVault)) revert InvalidAddress();
        if(address (0) == address (_beefyBoost)) revert InvalidAddress();

        __Ownable_init();
        __Context_init();
        __ERC20_init(
            string(abi.encodePacked("Nature ", lpToken.name(), " Vault")),
            string(abi.encodePacked("NV-", lpToken.symbol()))
        );
        __ERC4626_init(lpToken);

        beefyVault = _beefyVault;
        beefyBoost =_beefyBoost;
        lpToken.approve(address (beefyVault), type(uint256).max);
        IERC20Upgradeable(address (beefyVault)).approve(address(beefyBoost), type(uint256).max);
    }

    /// @notice Deposit underlying lpToken into the vault
    /// @param amount amount of lpToken to deposit
    /// @param receiver address to receive the lpTokens
    /// @return shares amount of shares minted to the receiver
    function deposit(uint256 amount, address receiver) public override whenNotPaused returns (uint256 shares) {
        if (receiver == address(0)) revert InvalidAddress();

        shares = previewDeposit(amount);
        if(shares == 0) revert ZeroShares();

        _mint(receiver, shares);
        IERC20Upgradeable(asset()).transferFrom(msg.sender, address(this), amount);
        _depositAndBoost(amount);

        emit Deposit(msg.sender, receiver, amount, shares);
    }

    /// @notice Withdraw underlying lpToken from the vault
    /// @param amount amount of lpToken to withdraw
    /// @param receiver address to receive the lpTokens
    /// @param owner owner of the vault token to be burnt
    function withdraw(uint256 amount, address receiver, address owner) public override whenNotPaused
        returns (uint256 shares) {
        if (receiver == address(0)) revert InvalidAddress();
        if (owner == address(0)) revert InvalidAddress();

        //shares is amount of vault token that will be burnt
        shares = previewWithdraw(amount);
        uint256 balanceBeforeWithdraw = IERC20Upgradeable(asset()).balanceOf(address(this));

        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) _approve(owner, msg.sender, allowed - shares);
        }

        uint256 beefyVaultShares = _convertToBeefyVaultShares(shares);
        beefyBoost.withdraw(beefyVaultShares);
        beefyVault.withdraw(beefyVaultShares);

        totalStake -= shares;
        _burn(owner, shares);

        uint256 amountUnderlying = IERC20Upgradeable(asset())
            .balanceOf(address(this)) - balanceBeforeWithdraw;
        IERC20Upgradeable(asset()).transfer(receiver, amountUnderlying);

        emit Withdraw(msg.sender, receiver, owner, amount, shares);
    }

    /// @notice Harvest reward from boosted pools
    function harvest() onlyOwner whenNotPaused public {
        beefyBoost.getReward();
        address rewardToken = beefyBoost.rewardToken();
        uint256 rewardEarned = IERC20Upgradeable(rewardToken).balanceOf(address(this));
        if(rewardEarned < 0) return;

        //swap the reward token for lp token of the beefy beefyVault
        uint256 amountSwappedFor = _swapRewardForAnyLpTokenPair(rewardToken, rewardEarned);
        _sellForLpToken(amountSwappedFor);

        uint256 amountOfLpToken =  IERC20Upgradeable(asset()).balanceOf(address(this));
        _depositAndBoost(amountOfLpToken);

        emit Harvest(msg.sender, rewardToken, rewardEarned);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    /// @notice Deposit underlying lpToken into beefy vault
    ///         and corresponding mooTokens into a balancer boosted pools
    /// @param  amount The amount of underlying tokens to deposit and boost
    function _depositAndBoost(uint256 amount) internal  {
        beefyVault.deposit(amount);

        uint256 mooTokens = beefyVault.balanceOf(address (this));
        totalStake += mooTokens;
        if(mooTokens == 0) revert ZeroMooTokens();
        beefyBoost.stake(mooTokens);
    }

    /// @notice Swap Stader Token (SD) for MATICX
    /// @param tokenIn token addressed of SD reward token to swap
    /// @param amountIn amount of SD reward token to swap
    /// @return The amount of MATICX tokens gotten from the swap
    function _swapRewardForAnyLpTokenPair(
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256) {
        return _singleSwap(
            tokenIn,
            amountIn
        );
    }

    /// @notice Exchanges MATICX for the underlying lp token of the vault in a Balancer Pool
    /// @param amount the amount of MATICX tokens to sell
    function _sellForLpToken(uint amount) internal {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0;
        amounts[1] = 0;
        amounts[2] = amount;

        _joinBalancerPool(
            address (this),
            address (this),
            amounts,
            0
        );
    }

    /// @notice Calculates the internal ERC4626 shares to burn
    /// @param shares takes as argument the internal ERC4626 shares to redeem
    /// @return The external BeefyVault shares to withdraw
    function _convertToBeefyVaultShares(uint256 shares) internal view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares.mulDivUp(totalStake, supply);
    }

    /* ========== VIEW FUNCTIONS ========== */
    /// @notice Calculates the internal ERC4626 shares to burn
    /// @param assets the amount of lp tokens to withdraw
    /// @return The total amount of shares to burn
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return The total amount of underlying tokens the Vault holds.
    function totalAssets() public view override returns (uint256) {
        return totalStake.mulDivUp(beefyVault.balance(), beefyVault.totalSupply());
    }
}
