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
    const [signer, feeTo, feeSigner, user1, user2, user3] = await ethers.getSigners();

    const TokenTemplate = await ethers.getContractFactory("TokenTemplate");
    const tokenA = await TokenTemplate.deploy();
    await tokenA.initialize("TokenA", "Test TokenA", BigNumber(1e26).toFixed(0), signer.address, signer.address);
    const tokenB = await TokenTemplate.deploy();
    await tokenB.initialize("TokenB", "Test TokenB", BigNumber(1e26).toFixed(0), signer.address, signer.address);
    // deployFactory
    const UniswapV3Factory = await ethers.getContractFactory("UniswapV3Factory");
    let factory = await UniswapV3Factory.deploy();
    // add pool
    await factory.addPool(tokenA.target, tokenB.target, 3000);

    const NonfungiblePositionManager = await ethers.getContractFactory("NonfungiblePositionManager");
    const nftManager = await NonfungiblePositionManager.deploy(tokenA.target, tokenB.target, factory.target);

    await tokenA.approve(nftManager, ethers.MaxUint256);
    await tokenB.approve(nftManager, ethers.MaxUint256);

    let tx = await nftManager.mint({
      token0: tokenA.target,
      token1: tokenB.target,
      fee: 3000,
      tickLower: -8000,
      tickUpper: 8000,
      amount0Desired: BigNumber(1e20).toFixed(),
      amount1Desired: BigNumber(1e20).toFixed(),
      amount0Min: 0,
      amount1Min: 1,
      recipient: signer.address,
      deadline: parseInt(Date.now() / 1000)
    });
    let receipt = await tx.wait();
    let logs = receipt.logs.find(event => event.fragment?.name == "Transfer");
    let [, , nftId] = logs.args;
    nftId = parseInt(nftId);

    const UniV3LPLocker = await ethers.getContractFactory("UniV3LPLocker");
    const locker = await UniV3LPLocker.deploy(nftManager.target, feeTo.address, feeSigner.address);
    return { signer, feeTo, feeSigner, user1, user2, user3, tokenA, tokenB, nftManager, locker, factory, nftId };
  };

  async function getCurrentBlock() {
    let blockInfo = await ethers.provider.getBlock();
    return blockInfo;
  }

  describe("test ownership", function () {
    it("test config", async function () {
      const { locker, tokenA, tokenB, factory, signer, feeTo, user1 } = await init();
      // test add nft manager
      const NonfungiblePositionManager = await ethers.getContractFactory("NonfungiblePositionManager");
      const nftManager = await NonfungiblePositionManager.deploy(tokenA.target, tokenB.target, factory.target);
      await locker.addSupportedNftManager(nftManager.target);
      // test update fee receiver
      await locker.updateFeeReceiver(user1.address);
      // test add fee
      await locker.addOrUpdateFee("TEST", 100, 100, BigNumber(1e20).toFixed(), tokenA.target);
      // test update fee
      await locker.addOrUpdateFee("TEST", 100, 100, 0, ethers.ZeroAddress);
      // test remove fee
      await locker.removeFee("TEST");
    })
  });

  describe("test lock nft", function () {
    it("test lock nft", async function () {
      const { locker, signer, feeTo, nftManager, nftId, user1} = await init();
      // set approval
      await nftManager.approve(locker.target, nftId);
      // get current time
      let blockInfo = await getCurrentBlock();
      let endTime = blockInfo.timestamp + 200;
      let tx = await locker.lock(nftManager.target, nftId, signer.address, user1.address, endTime, "DEFAULT");
      let receipt = await tx.wait();
      let log = receipt.logs.find(e => e.fragment?.name == 'OnLock');
      const [lockId] = log.args;
    }),
    it("test custorm fee", async function () {
      const { locker, signer, feeTo, feeSigner, nftManager, nftId, user1 } = await init();
      // set approval
      await nftManager.approve(locker.target, nftId);
      // get current time
      let blockInfo = await getCurrentBlock();
      let endTime = blockInfo.timestamp + 200;
      let fee = {
        name: 'CUSTOM', 
        lpFee: 0,
        collectFee: 0,
        lockFee: 0,
        lockFeeToken: ethers.ZeroAddress
      }
      const messageHash = ethers.solidityPackedKeccak256(
        ["uint256", "address", "string", "uint256", "uint256", "uint256", "address"],
        [network.config.chainId, signer.address, fee.name, fee.lpFee, fee.collectFee, fee.lockFee, fee.lockFeeToken]
      );
      const signature = await feeSigner.signMessage(ethers.getBytes(messageHash));
      await locker.lockWithCustomFee(
        nftManager.target, 
        nftId, 
        signer.address,
        user1.address, 
        endTime,
        signature,
        fee
      )
    }),
    it("test increase liquidity", async function () {
      const { locker, tokenA, tokenB, signer, feeTo, nftManager, nftId, user1 } = await init();
      // set approval
      await nftManager.approve(locker.target, nftId);
      // get current time
      let blockInfo = await getCurrentBlock();
      let endTime = parseInt(blockInfo.timestamp + 200);
      let tx = await locker.lock(nftManager.target, nftId, signer.address, user1.address, endTime, "DEFAULT");
      let receipt = await tx.wait();
      let log = receipt.logs.find(e => e.fragment?.name =='OnLock');
      const [lockId] = log.args;
      // approve tokenA/tokenB to locker
      await tokenA.approve(locker.target, ethers.MaxUint256);
      await tokenB.approve(locker.target, ethers.MaxUint256);
      // increase liquidity
      await locker.increaseLiquidity(lockId, {
        tokenId: nftId,
        amount0Desired: BigNumber(1e20).toFixed(),
        amount1Desired: BigNumber(1e20).toFixed(),
        amount0Min: 0,
        amount1Min: 0,
        deadline: parseInt(endTime + 100)
      });
    }),
    it("test decrease liquidity", async function () {
      const { locker, tokenA, tokenB, signer, feeTo, nftManager, nftId, user1 } = await init();
      // set approval
      await nftManager.approve(locker.target, nftId);
      // get current time
      let blockInfo = await getCurrentBlock();
      let endTime = parseInt(blockInfo.timestamp + 200);
      let tx = await locker.lock(nftManager.target, nftId, signer.address, user1.address, endTime, "DEFAULT");
      let receipt = await tx.wait();
      let log = receipt.logs.find(e => e.fragment?.name == 'OnLock');
      const [lockId] = log.args;
      await expect(
        locker.decreaseLiquidity(lockId, {
          tokenId: nftId,
          liquidity: BigNumber(1e18).toFixed(),
          amount0Min: 0,
          amount1Min: 0,
          deadline: parseInt(endTime + 100)
        })
      ).to.be.revertedWith('NOT YET');
      // increase timestamp
      await ethers.provider.send("evm_increaseTime", [200]);
      await ethers.provider.send("evm_mine", []);
      // decreaseLiquidity
      await locker.decreaseLiquidity(lockId, {
        tokenId: nftId,
        liquidity: BigNumber(1e18).toFixed(),
        amount0Min: 0,
        amount1Min: 0,
        deadline: parseInt(endTime + 100)
      });
    }),
    it("test collect", async function () {
      const { locker, tokenA, tokenB, signer, feeTo, nftManager, nftId, user1, user2 } = await init();
      // set approval
      await nftManager.approve(locker.target, nftId);
      // get current time
      let blockInfo = await getCurrentBlock();
      let endTime = parseInt(blockInfo.timestamp + 200);
      let tx = await locker.lock(nftManager.target, nftId, signer.address, user1.address, endTime, "DEFAULT");
      let receipt = await tx.wait();
      let log = receipt.logs.find(e => e.fragment?.name == 'OnLock');
      const [lockId] = log.args;

      // collect
      await locker.collect(lockId, user2.address, BigNumber(1e26).toFixed(), BigNumber(1e26).toFixed());
      await expect(
        await tokenA.balanceOf(user2.address)
      ).to.greaterThan(0);
    }),
    it("test transfer lock", async function () {
      const { locker, tokenA, tokenB, signer, feeTo, nftManager, nftId, user1, user2 } = await init();
      // set approval
      await nftManager.approve(locker.target, nftId);
      // get current time
      let blockInfo = await getCurrentBlock();
      let endTime = parseInt(blockInfo.timestamp + 200);
      let tx = await locker.lock(nftManager.target, nftId, signer.address, user1.address, endTime, "DEFAULT");
      let receipt = await tx.wait();
      let log = receipt.logs.find(e => e.fragment?.name == 'OnLock');
      const [lockId] = log.args;
      // transfer lock ownership
      await expect(
        await locker.transferLock(lockId, user2.address)
      ).to.emit(locker, "OnLockPendingTransfer");
      // accept lock ownership
      await expect(
        await locker.connect(user2).acceptLock(lockId)
      ).to.emit(locker, "OnLockTransferred");
    }),
    it("test unlock", async function () {
      const { locker, tokenA, tokenB, signer, feeTo, nftManager, nftId, user1, user2 } = await init();
      // set approval
      await nftManager.approve(locker.target, nftId);
      // get current time
      let blockInfo = await getCurrentBlock();
      let endTime = parseInt(blockInfo.timestamp + 200);
      let tx = await locker.lock(nftManager.target, nftId, signer.address, user1.address, endTime, "DEFAULT");
      let receipt = await tx.wait();
      let log = receipt.logs.find(e => e.fragment?.name == 'OnLock');
      const [lockId] = log.args;
      // increase timestamp
      await ethers.provider.send("evm_increaseTime", [200]);
      await ethers.provider.send("evm_mine", []);
      // check nft owner is locker
      await expect(
        await nftManager.ownerOf(nftId)
      ).to.equal(locker.target);
      // unlock
      await locker.unlock(lockId);
      // check nft owner is signer
      await expect(
        await nftManager.ownerOf(nftId)
      ).to.equal(signer.address);
    }),
    it("test relock", async function () {
      const { locker, tokenA, tokenB, signer, feeTo, nftManager, nftId, user1, user2 } = await init();
      // set approval
      await nftManager.approve(locker.target, nftId);
      // get current time
      let blockInfo = await getCurrentBlock();
      let endTime = parseInt(blockInfo.timestamp + 200);
      let tx = await locker.lock(nftManager.target, nftId, signer.address, user1.address, endTime, "DEFAULT");
      let receipt = await tx.wait();
      let log = receipt.logs.find(e => e.fragment?.name == 'OnLock');
      const [lockId] = log.args;
      // extend lock up period
      await locker.relock(lockId, parseInt(endTime + 200));
      // increase timestamp
      await ethers.provider.send("evm_increaseTime", [400]);
      await ethers.provider.send("evm_mine", []);
      // extend lock up period
      await locker.relock(lockId, parseInt(endTime + 400));
    })
  });

});
