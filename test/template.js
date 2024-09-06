const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers, artifacts } = require("hardhat");
const { default: BigNumber } = require("bignumber.js");

describe("token template test", function () {
  async function init() {
    
    const TokenTemplate = await ethers.getContractFactory("TokenTemplate");
    const template = await TokenTemplate.deploy();
    
    const [signer, receiver, feeTo, user1, user2, user3, user4] = await ethers.getSigners();
    
    return { signer, receiver, feeTo, user1, user2, user3, template };
  }

  async function initialize(template, signer, receiver) {
    let symbol = 'TEST';
    let name = 'Test Token';
    let totalSupply = BigNumber(1e24).toFixed(0);
    let owner = signer.address;
    let initReceiver = receiver.address;
    await template.initialize(symbol, name, totalSupply, owner, initReceiver);
    return { symbol, name, totalSupply, owner, initReceiver };
  }

  async function deployAndInitialize() {
    const initRet = await init();
    const ret = await initialize(initRet.template, initRet.signer, initRet.receiver);
    return {...initRet, ...ret};
  }

  describe("test deploy", function () {
    it("test only can initialize once", async function () {
      const { template, signer, receiver } = await deployAndInitialize();
      await expect(initialize(template, signer, receiver)).to.be.reverted;
    }),
    it("test only can devInit once", async function () {
      const { template, signer, feeTo, receiver } = await deployAndInitialize();
      await template.devInit([], [], [], 100, 100, feeTo.address);
      await expect(template.devInit([], [], [], 100, 100, feeTo.address)).to.be.reverted;
    }),
    it("test initialize meta", async function () {
      const { signer, receiver, template, symbol, name, totalSupply, owner, initReceiver } = await deployAndInitialize();
      await expect(await template.owner()).to.equal(owner);
      await expect(await template.symbol()).to.equal(symbol);
      await expect(await template.name()).to.equal(name);
      await expect(await template.totalSupply()).to.equal(totalSupply);
      await expect(await template.balanceOf(initReceiver)).to.equal(totalSupply);
    }),
    it("test whitelist", async function () {
      const { template, signer, feeTo, user1, user2, receiver } = await deployAndInitialize();
      // user1 in whitelist; user2 is pool
      await template.devInit([], [user1.address], [user2.address], 100, 100, feeTo.address);
      // transfer to user1
      await template.connect(receiver).transfer(user1.address, BigNumber(1e23).toFixed(0));
      // check user1 balance
      await expect(await template.balanceOf(user1.address)).to.equal(BigNumber(1e23).toFixed(0));
      // user1 transfer to pool 
      await template.connect(user1).transfer(user2.address, BigNumber(1e23).toFixed(0));
      // check pool received (user1 in whiteList don't need take fee)
      await expect(await template.balanceOf(user2.address)).to.equal(BigNumber(1e23).toFixed(0));
    }),
    it("test blacklist", async function () {
      const { template, signer, feeTo, user1, user2, receiver } = await deployAndInitialize();
      // user1 in blacklist; user2 is pool
      await template.devInit([user1.address], [], [user2.address], 100, 100, feeTo.address);
      // transfer to user1
      await expect(template.connect(receiver).transfer(user1.address, BigNumber(1e23).toFixed(0))).to.be.reverted;
      // remove blacklist
      await template.connect(signer).removeBlacklist();
      // transfer to user1
      await template.connect(receiver).transfer(user1.address, BigNumber(1e22).toFixed(0));

    }),
    it("test buyTax & sellTax", async function () {
      const { template, signer, feeTo, user1, user2, user3, receiver } = await deployAndInitialize();
      // user1 in blacklist; user2 is pool
      await template.devInit([], [], [user2.address], 100, 100, feeTo.address);
      // receiver transfer to pool
      let amount = BigNumber(1e22).toFixed(0);
      await template.connect(receiver).transfer(user2.address, amount);
      // check feeTo received 1%
      await expect(await template.balanceOf(feeTo.address)).to.equal(BigNumber(1e20).toFixed(0));
      // check pool received 99%
      await expect(await template.balanceOf(user2.address)).to.equal(BigNumber(1e22-1e20).toFixed(0));
      // pool transfer to user3
      await template.connect(user2).transfer(user3.address, BigNumber(1e20).toFixed(0));
      // check user3 received 
      await expect(await template.balanceOf(user3.address)).to.equal(BigNumber(1e20 - 1e18).toFixed(0));
    }),
    it("test remove tax", async function () {
      const { template, signer, feeTo, user1, user2, user3, receiver } = await deployAndInitialize();
      // user1 in blacklist; user2 is pool
      await template.devInit([], [], [user2.address], 100, 100, feeTo.address);
      // transfer amount
      let amount = BigNumber(1e22).toFixed(0);
      // remove tax
      await template.connect(signer).removeTax();
      // receiver transfer to pool
      await template.connect(receiver).transfer(user2.address, amount);
      // check feeTo received 0%
      await expect(await template.balanceOf(feeTo.address)).to.equal(0);
      // check pool received 100%
      await expect(await template.balanceOf(user2.address)).to.equal(amount);
      // pool transfer to user3
      await template.connect(user2).transfer(user3.address, BigNumber(1e20).toFixed(0));
      // check user3 received 
      await expect(await template.balanceOf(user3.address)).to.equal(BigNumber(1e20).toFixed(0));
    })
    // it("test anti-whale", async function () {
    //   const { template, signer, feeTo, user1, user2, user3, receiver } = await deployAndInitialize();
    //   let antiWhaleLimit = BigNumber(1e22).toFixed(0);
    //   // user1 in blacklist; user2 is pool
    //   await template.devInit([], [], [user2.address], 100, 100, feeTo.address, antiWhaleLimit, antiWhaleLimit);
    //   // receiver transfer to pool
    //   await expect(template.connect(receiver).transfer(user3.address, BigNumber(1e23).toFixed(0))).to.be.reverted;
    //   // pool should not be anti-whale
    //   await template.connect(receiver).transfer(user2.address, BigNumber(1e22).toFixed(0));
    //   await template.connect(receiver).transfer(user2.address, BigNumber(1e22).toFixed(0));

    //   // remove anti-whale
    //   await template.connect(signer).removeAntiWhale();
    //   await template.connect(receiver).transfer(user3.address, BigNumber(1e23).toFixed(0));

    // })
  });
});
