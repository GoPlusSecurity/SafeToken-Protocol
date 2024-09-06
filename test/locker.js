const {
  time,
  loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { ethers, artifacts } = require("hardhat");
const { default: BigNumber } = require("bignumber.js");

describe("locker test", function () {
  async function init() {
    
    const TokenTemplate = await ethers.getContractFactory("TokenTemplate");
    const tokenA = await TokenTemplate.deploy();
    const tokenB = await TokenTemplate.deploy();
    
    const [signer, user1, user2, user3] = await ethers.getSigners();
    
    const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
    const factory = await UniswapV2Factory.deploy();
    const tx = await factory.createPair(tokenA.target, tokenB.target);
    const receipt = await tx.wait();
    let logs = receipt.logs.find(event => event.fragment?.name == "PairCreated");
    const [, , pairAddr, index] = logs.args;

    const UniswapV2Pair = await ethers.getContractFactory("UniswapV2Pair");
    const pair = UniswapV2Pair.attach(pairAddr);
    return { signer, user1, user2, user3, tokenA, tokenB, factory, pair };
  }

  describe("test deploy", function () {
    it("test params", async function () {
      const { factory, pair } = await init();
    });
  });
});
