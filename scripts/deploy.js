// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.

const { ethers, network } = require("hardhat");
const { default: BigNumber } = require("bignumber.js");

async function main() {

  const TokenTemplate = await ethers.getContractFactory("TokenTemplate");
  const template = await TokenTemplate.deploy(hook.target);
  await template.waitForDeployment();
  console.log("template --> ", template.target);

  const [signer, feeTo] = await ethers.getSigners();

  const ERC20Factory = await ethers.getContractFactory("ERC20Factory");
  const factory = await ERC20Factory.deploy(BigNumber(1e16).toFixed(0), feeTo.address);
  await factory.waitForDeployment();
  console.log("factory --> ", factory.target);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
