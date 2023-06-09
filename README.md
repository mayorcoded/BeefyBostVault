# BeefyBoostStrategy


This project is a proof of concept for how to invest in Beefy Vaults and Beefy Boosted Pools. The project is a strategy 
contract that carries out the following functions:

1. Picks a Beefy Vault with active Boost to invest in.
2. When a user deposits their LP token into the strategy contract, the strategy vault deposits the user funds 
(the LP-token) into the Beefy Vault picked in (1) above and stake the mooTokens earned from the BeefyVault into the Booster.
3. When a user tries to withdraw, the contract should return the appropriate amount of Lp-Token to the user.
4. When the reward from the boosted pool is harvested, the strategy contract should claim the Booster rewards and 
sell them for the Lp-Token required by the BeefyVault and redeposit those new Lp-Token into the BeefyVault and BeefyBooster.
5. New deposits and withdrawals should take these compounded assets into account. (Increase share price).

To run the project, take the following steps
```shell
1. clone the repo
2. run `yarn` in your terminal to install all dependencies
3. rename .env.templet to .env, add the necessary environmenta variables to the .env file
4. run the test using `npx hardhat test` in your terminal 
```
