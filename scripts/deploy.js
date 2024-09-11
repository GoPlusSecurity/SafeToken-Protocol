// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.

const { ethers, network } = require("hardhat");
const { default: BigNumber } = require("bignumber.js");

async function main() {
  const { chainId, feeTo, nftManager, customFeeSigner } = network.config;
  console.log('chainId --> ', chainId);
  console.log('nftManager --> ', nftManager);
  console.log('feeTo --> ', feeTo);
  console.log('customFeeSigner --> ', customFeeSigner);

  const TokenTemplate = await ethers.getContractFactory("TokenTemplate");
  const template = await TokenTemplate.deploy();
  await template.waitForDeployment();
  console.log("template --> ", template.target);

  const [signer] = await ethers.getSigners();

  const SafeTokenFactory = await ethers.getContractFactory("SafeTokenFactory");
  const factory = await SafeTokenFactory.deploy();
  await factory.waitForDeployment();
  console.log("factory --> ", factory.target);

  let addTempTx = await factory.updateTemplates(1, template.target);
  let addTempTxReceipt = await addTempTx.wait();

  const TokenLocker = await ethers.getContractFactory("TokenLocker");
  const locker = await TokenLocker.deploy(feeTo);
  await locker.waitForDeployment();
  console.log("locker --> ", locker.target);

  const UniV3LPLocker = await ethers.getContractFactory("UniV3LPLocker");
  const uniV3Locker = await UniV3LPLocker.deploy(nftManager, feeTo, customFeeSigner);
  await uniV3Locker.waitForDeployment();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
