// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";

import "../interfaces/IBalancerV2Vault.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v2-interfaces/contracts/pool-stable/StablePoolUserData.sol";
import "@balancer-labs/v2-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";


abstract contract BalancerV2Vault {
    address public constant MATIC_X = 0xfa68FB4628DFF1028CFEc22b4162FCcd0d45efb6;
    IVault private constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    bytes32 public constant SD_MATICX_POOL_ID = 0x4973f591784d9c94052a6c3ebd553fcd37bb0e5500020000000000000000087f;
    bytes32 public constant MATICX_BBA_WMATIC_POOL_ID = 0xe78b25c06db117fdf8f98583cdaaa6c92b79e917000000000000000000000b2b;

    /**
     * @dev Internal function to swap two tokens through BalancerV2 using a single hop
     * @param tokenIn Token being sent
     * @param amountIn Amount of tokenIn being swapped
     * @return amountOut Amount of token swaped for
     */
    function _singleSwap(
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(vault), amountIn);

        IVault.SingleSwap memory swap;
        swap.poolId = SD_MATICX_POOL_ID;
        swap.kind = IVault.SwapKind.GIVEN_IN;
        swap.assetIn = IAsset(tokenIn);
        swap.assetOut = IAsset(MATIC_X);
        swap.amount = amountIn;
        swap.userData = new bytes(0);
        return vault.swap(swap, _fundManagement(), 0, block.timestamp);
    }

    /**
     * @dev Internal function to sell some MATICX for the underlying lpToken
     * @param sender The sender of the transaction
     * @param recipient The recipient of the lpTokens
     * @param amountsIn[] Amount of tokens being swapped
     * @param minBptAmountOut Minimum amount of balancer pool tokens to be minder
     */
    function _joinBalancerPool(
        address sender,
        address recipient,
        uint256[] memory amountsIn,
        uint256 minBptAmountOut
    ) internal {
        IERC20(MATIC_X).approve(address(vault), amountsIn[2]);
        (IERC20[] memory tokens, , ) = vault.getPoolTokens(MATICX_BBA_WMATIC_POOL_ID);

        // Use BalancerErrors to validate input
        _require(amountsIn.length == tokens.length, Errors.INPUT_LENGTH_MISMATCH);

        // Encode the userData for a multi-token join
        bytes memory userData = abi.encode(
            StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            amountsIn,
            minBptAmountOut
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: _asIAsset(tokens),
            maxAmountsIn: amountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        // Call the Vault to join the pool
        vault.joinPool(MATICX_BBA_WMATIC_POOL_ID, sender, recipient, request);
    }


    /**
    * @dev Internal function to build the fund management struct required by Balancer for swaps
    */
    function _fundManagement() private view returns (IVault.FundManagement memory) {
        return IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(msg.sender),
            toInternalBalance: false
        });
    }

    function _asIAsset(IERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
    }
}
