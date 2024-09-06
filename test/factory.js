const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers, artifacts } = require("hardhat");
const { default: BigNumber } = require("bignumber.js");

describe("ERC20 Factory test", function () {
  async function init() {
    
    const TokenTemplate = await ethers.getContractFactory("TokenTemplate");
    const template = await TokenTemplate.deploy();
    
    const [signer] = await ethers.getSigners();
    
    const ERC20Factory = await ethers.getContractFactory("ERC20Factory");
    const factory = await ERC20Factory.deploy();
    return { signer, template, factory };
  }

  describe("test deploy", function () {
    it("test params", async function () {

      const { signer, template, factory } = await init();

      // update template and check it
      await factory.updateTemplates(1, template.target);
      const temp = await factory._templates(1);
      expect(temp).to.equal(template.target);

      // let tempCode = await ethers.provider.getCode(template.target)；
      // console.log('tempCode length --> ', tempCode.length);


      // computeTokenAddress
      let computeAddress = await factory.cumputeTokenAddress(1);

      let price = BigNumber(1e16).toFixed(0);
      const tx = await factory.createToken(1, "Test", "Test Token", BigNumber(1e24).toFixed(0), signer.address, signer.address);
      const receipt = await tx.wait();
      let logs = receipt.logs.find(event => event.fragment?.name == "TokenCreated");
      const [key, tokenAddress, symbol, name, totalsupply, owner, initReceiver] = logs.args;
      await expect(computeAddress).to.equal(tokenAddress);

      // let tokenCode = await ethers.provider.getCode(tokenAddress)；
      // console.log('tokenCode length --> ', tokenCode.length);


      const TokenTemplate = await ethers.getContractFactory("TokenTemplate");
      const tokenObj = TokenTemplate.attach(tokenAddress);
      await expect(await tokenObj.owner()).to.equal(owner);
      await expect(await tokenObj.symbol()).to.equal(symbol);
      await expect(await tokenObj.name()).to.equal(name);
      await expect(await tokenObj.totalSupply()).to.equal(totalsupply);
      await expect(await tokenObj.balanceOf(initReceiver)).to.equal(totalsupply);
    });
  });
});
