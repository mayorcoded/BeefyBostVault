import { expect } from "chai";
import {  deploy, fp, impersonate, instanceAt } from '@mimic-fi/v1-helpers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { BeefyBoostStrategy, ERC20Upgradeable } from "../typechain";

const MATICX_BBA_WMATIC = "0xE78b25c06dB117fdF8F98583CDaaa6c92B79E917";
const BEEFY_VAULT = "0x4C98CB046c3eb7e3ae7Eb49a33D6f3386Ec2b9D9";
const BEEFY_BOOST = "0x2e5598608A4436dBb9c34CE6862B5AF882F49a6B";
const WHALE = "0xd00297757a4bf8cca6305a45898be5791d642f79";

describe("BeefyERC4626Vault", () => {
  let vault: BeefyBoostStrategy;
  let whale: SignerWithAddress;
  let lpToken: ERC20Upgradeable;

  before('create BeefyERC4626Vault contract', async () => {
    const args: any[] | undefined = [];
    vault = (await deploy('BeefyBoostStrategy', args)) as BeefyBoostStrategy;
    await vault.initialize(MATICX_BBA_WMATIC, BEEFY_VAULT, BEEFY_BOOST);
  })

  before('load tokens and impersonate accounts', async () => {
    lpToken = (await instanceAt('ERC20Upgradeable', MATICX_BBA_WMATIC)) as ERC20Upgradeable;
    whale = await impersonate(WHALE, fp(5_000));
  })

  it("should deposit some lp tokens and earn some vault shares", async () => {
    const amount = fp(500);

    const prevLpTokenBal = await lpToken.balanceOf(whale.address);
    const prevVaultTokenBal = await vault.balanceOf(whale.address);

    await lpToken.connect(whale).approve(vault.address, amount);
    await vault.connect(whale).deposit(amount, whale.address);

    const currLpTokenBal = await lpToken.balanceOf(whale.address);
    const currVaultTokenBal = await vault.balanceOf(whale.address);

    expect(currVaultTokenBal).to.be.at.least(prevVaultTokenBal);
    expect(prevLpTokenBal.sub(currLpTokenBal)).to.equals(amount);
  })

  it("should withdraw some lp tokens for shares", async () => {
    const amount = fp(300);

    const prevLpTokenBal = await lpToken.balanceOf(whale.address);
    await vault.connect(whale).withdraw(amount, whale.address, whale.address);

    const currLpTokenBal = await lpToken.balanceOf(whale.address);
    expect(currLpTokenBal.sub(prevLpTokenBal)).to.equals(amount);
  })

  it("should only be harvested by owner", async () => {
    await expect(vault.connect(whale).harvest())
      .revertedWith("Ownable: caller is not the owner");
  })

  it("should harvest some reward from the boosted pools", async () => {
    await expect(vault.harvest())
      .emit(vault, "Harvest");
  })
});
