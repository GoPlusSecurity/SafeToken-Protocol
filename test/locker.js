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
    const [signer, feeTo, user1, user2, user3] = await ethers.getSigners();

    const TokenTemplate = await ethers.getContractFactory("TokenTemplate");
    const tokenA = await TokenTemplate.deploy();
    await tokenA.initialize("TokenA", "Test TokenA", BigNumber(1e26).toFixed(0), signer.address, signer.address);
    const tokenB = await TokenTemplate.deploy();
    await tokenB.initialize("TokenB", "Test TokenB", BigNumber(1e26).toFixed(0), signer.address, signer.address);


    const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
    const factory = await UniswapV2Factory.deploy();
    const tx = await factory.createPair(tokenA.target, tokenB.target);
    const receipt = await tx.wait();
    let logs = receipt.logs.find(event => event.fragment?.name == "PairCreated");
    const [, , pairAddr, index] = logs.args;

    await tokenA.approve(pairAddr, ethers.MaxUint256);
    await tokenB.approve(pairAddr, ethers.MaxUint256);

    const UniswapV2Pair = await ethers.getContractFactory("UniswapV2Pair");
    const pair = UniswapV2Pair.attach(pairAddr);

    await pair.mint(signer.address);

    const TokenLocker = await ethers.getContractFactory("TokenLocker");
    const locker = await TokenLocker.deploy(feeTo.address);
    return { signer, feeTo, user1, user2, user3, tokenA, tokenB, factory, pair, locker };
  };

  async function getCurrentBlock() {
    let blockInfo = await ethers.provider.getBlock();
    return blockInfo;
  }

  describe("test ownership", function () {
    it("test lock token", async function () {
      const { locker, tokenA, signer, feeTo } = await init();
      await locker.addOrUpdateFee("TEST", 100, 0, ethers.ZeroAddress, false);
      expect(
        locker.connect(feeTo).addOrUpdateFee("TEST", 100, 0, ethers.ZeroAddress, false)
      ).to.be.reverted;
      expect(
        locker.updateFeeReceiver(ethers.ZeroAddress)
      ).to.be.reverted;
    })
  });

  describe("test lock token", function () {
    it("test lock token", async function () {
      const { locker, tokenA, signer, feeTo } = await init();
      let currentBlock = await getCurrentBlock();
      let endTime = currentBlock.timestamp + 200;
      await tokenA.approve(locker.target, ethers.MaxUint256);
      expect(
        locker.lock(tokenA.target, "TOKEN", signer.address, BigNumber(1e20).toFixed(), endTime)
      ).to.be.revertedWith("Fee");
      let beforeBalance = await ethers.provider.getBalance(feeTo.address);
      await locker.lock(tokenA.target, "TOKEN", signer.address, BigNumber(1e20).toFixed(), endTime, { value: BigNumber(12 * 10 ** 16).toFixed() });
      let afterBalance = await ethers.provider.getBalance(feeTo.address);
      // check fee
      expect(BigNumber(afterBalance).minus(beforeBalance)).to.equal(BigNumber(12 * 10 ** 16));
      expect(
        locker.lock(tokenA.target, "LP_ONLY", signer.address, BigNumber(1e20).toFixed(), endTime)
      ).to.be.revertedWith("FeeName not supported for Token");
    }),
    it("test update token", async function () {
      const { locker, tokenA, signer, feeTo } = await init();
      // set approval
      await tokenA.approve(locker.target, ethers.MaxUint256);
      // endtime
      let currentBlock = await getCurrentBlock();
      let endTime = currentBlock.timestamp + 200;
      // lock and get lockId from event
      let tx = await locker.lock(tokenA.target, "TOKEN", signer.address, BigNumber(1e20).toFixed(), endTime, { value: BigNumber(12 * 10 ** 16).toFixed() });
      const receipt = await tx.wait();
      let logs = receipt.logs.find(event => event.fragment?.name == "OnLock");
      const [lockId] = logs.args;

      // check lock moreToken
      expect(
        locker.updateLock(lockId, 0, ++endTime)
      ).to.be.revertedWith("MoreAmount is 0");
      await locker.updateLock(lockId, BigNumber(1e20).toFixed(), ++endTime, { value: BigNumber(12 * 10 ** 16).toFixed() });
      // check set endTime
      expect(
        locker.updateLock(lockId, 1, endTime - 1)
      ).to.be.revertedWith("New EndTime not allowed");
      await locker.updateLock(lockId, 1, parseInt(++endTime), { value: BigNumber(12 * 10 ** 16).toFixed() });

    }),
    it("test unlock token", async function () {
      const { locker, tokenA, signer, feeTo } = await init();
      // set approval
      await tokenA.approve(locker.target, ethers.MaxUint256);
      // endtime
      let lockAmount = BigNumber(1e20).toFixed();
      let currentBlock = await getCurrentBlock();
      let endTime = currentBlock.timestamp + 200;
      // lock and get lockId from event
      let tx = await locker.lock(tokenA.target, "TOKEN", signer.address, lockAmount, endTime,
        { value: BigNumber(12 * 10 ** 16).toFixed() }
      );
      const receipt = await tx.wait();
      let OnLock = receipt.logs.find(event => event.fragment?.name == "OnLock");
      const [lockId] = OnLock.args;
      let lockInfo = await locker.locks(lockId);

      // increase timestamp
      await ethers.provider.send("evm_increaseTime", [100]);
      await ethers.provider.send("evm_mine", []);
      expect(
        locker.unlock(lockId)
      ).to.be.revertedWith('Before endTime');

      // 有点奇怪，两次increaseTime 中间不查一下lockInfo，锁仓 amount 会变成 0
      lockInfo = await locker.locks(lockId);

      // increase timestamp
      await ethers.provider.send("evm_increaseTime", [100]);
      await ethers.provider.send("evm_mine", []);
      lockInfo = await locker.locks(lockId);
      // unlock
      let unlockTx = await locker.unlock(lockId);
      let unlockReceipt = await unlockTx.wait();
      let OnUnlock = unlockReceipt.logs.find(event => event.fragment?.name == "OnUnlock");
      // console.log(OnUnlock.args);
      const [, , owner, amount] = OnUnlock.args;
      expect(owner).to.equal(signer.address);
      expect(amount).to.equal(lockAmount);
    }),
    it("test transfer lock", async function () {
      const { locker, tokenA, signer, feeTo, user1 } = await init();
      // set approval
      await tokenA.approve(locker.target, ethers.MaxUint256);
      // endtime
      let lockAmount = BigNumber(1e20).toFixed();
      let currentBlock = await getCurrentBlock();
      let endTime = currentBlock.timestamp + 200;
      // lock and get lockId from event
      let tx = await locker.lock(tokenA.target, "TOKEN", signer.address, lockAmount, endTime, { value: BigNumber(12 * 10 ** 16).toFixed() });
      const receipt = await tx.wait();
      let OnLock = receipt.logs.find(event => event.fragment?.name == "OnLock");
      const [lockId] = OnLock.args;

      // transfer lock owner
      await expect(
        await locker.transferLock(lockId, user1.address)
      ).to.be.emit(locker, "OnLockPendingTransfer");
      // accept lock owner
      await locker.connect(user1).acceptLock(lockId);
      let lockInfo = await locker.locks(lockId);
      expect(lockInfo.owner).to.equal(user1.address);
    }),
    it("test vesting token", async function () {
      const { locker, tokenA, signer, feeTo, user1 } = await init();
      // set approval
      await tokenA.approve(locker.target, ethers.MaxUint256);
      // endtime
      let lockAmount = BigNumber(1e20).toFixed();
      let currentBlock = await getCurrentBlock();
      let endTime = currentBlock.timestamp + 200;
      let params = {
        token: tokenA.target,
        tgeBps: 2000, // 20 %
        cycleBps: 2000, // 20% per cycle
        owner: user1.address,
        amount: lockAmount,
        tgeTime: endTime,
        cycle: 100
      }
      let tx = await locker.vestingLock(params, "TOKEN", { value: BigNumber(12 * 10 ** 16).toFixed() });
      const receipt = await tx.wait();
      let OnLock = receipt.logs.find(event => event.fragment?.name == "OnLock");
      const [lockId] = OnLock.args;

      let lockInfo = await locker.locks(lockId);

      // increase timestamp
      await ethers.provider.send("evm_increaseTime", [200]);
      await ethers.provider.send("evm_mine", []);

      await locker.connect(user1).unlock(lockId);
      lockInfo = await locker.locks(lockId);
      let tgeAmount = BigNumber(lockAmount).multipliedBy(2000).dividedBy(10000).toFixed(0);
      // check unlocked amount
      expect(BigNumber(lockInfo.unlockedAmount)).to.equal(tgeAmount);
      // check owner received
      await expect(await tokenA.balanceOf(user1.address)).to.equal(tgeAmount);

      // increase 200 will unlock 2 cycle = 40 % 
      await ethers.provider.send("evm_increaseTime", [200]);
      await ethers.provider.send("evm_mine", []);

      // unlock
      await locker.connect(user1).unlock(lockId);
      lockInfo = await locker.locks(lockId);
      let unlockedAmount = BigNumber(lockAmount).multipliedBy(6000).dividedBy(10000).toFixed(0);
      // check unlocked amount
      expect(BigNumber(lockInfo.unlockedAmount)).to.equal(unlockedAmount);
      // check owner received
      await expect(await tokenA.balanceOf(user1.address)).to.equal(unlockedAmount);
    })
  });

  describe("test lock lpToken", function () {
    it("test lock lp", async function () {
      const { factory, tokenA, tokenB, pair, locker, signer, feeTo, user1 } = await init();
      let currentBlock = await getCurrentBlock();
      let endTime = currentBlock.timestamp + 200;
      await pair.approve(locker.target, ethers.MaxUint256);
      let lockAmount = BigNumber(1e21).toFixed(0);
      expect(
        locker.lock(pair.target, "TOKEN", signer.address, lockAmount, endTime)
      ).to.be.revertedWith("Fee");

      let beforeFee = await tokenA.balanceOf(feeTo.address);
      expect(beforeFee).to.equal(0);
      await locker.lock(pair.target, "LP_ONLY", user1.address, lockAmount, endTime);
      let afterFee = await tokenA.balanceOf(feeTo.address);
      expect(afterFee).to.greaterThan(0);
    }),
    it("test update lp", async function () {
      const { factory, tokenA, tokenB, pair, locker, signer, feeTo, user1 } = await init();
      let currentBlock = await getCurrentBlock();
      let endTime = currentBlock.timestamp + 200;
      await pair.approve(locker.target, ethers.MaxUint256);
      let lockAmount = BigNumber(1e20).toFixed(0);
      // lock and get lockId from event
      let tx = await locker.lock(pair.target, "LP_ONLY", signer.address, lockAmount, endTime);
      const receipt = await tx.wait();
      let logs = receipt.logs.find(event => event.fragment?.name == "OnLock");
      const [lockId] = logs.args;

      // check lock more
      await locker.updateLock(lockId, BigNumber(1e18).toFixed(), ++endTime);
      // check set endTime
      await locker.updateLock(lockId, BigNumber(1e18).toFixed(), parseInt(++endTime));
    }),
    it("test unlock lp", async function () {
      const { factory, tokenA, tokenB, pair, locker, signer, feeTo, user1 } = await init();
      let currentBlock = await getCurrentBlock();
      let endTime = currentBlock.timestamp + 200;
      await pair.approve(locker.target, ethers.MaxUint256);
      let lockAmount = BigNumber(1e20).toFixed(0);
      // lock and get lockId from event
      let tx = await locker.lock(pair.target, "LP_ONLY", signer.address, lockAmount, endTime);
      const receipt = await tx.wait();
      let logs = receipt.logs.find(event => event.fragment?.name == "OnLock");
      const [lockId] = logs.args;
      let lockInfoBefore = await locker.locks(lockId);
      // console.log(lockInfoBefore);
      expect(lockInfoBefore.unlockedAmount).to.equal(0);

      // increase timestamp
      await ethers.provider.send("evm_increaseTime", [100]);
      await ethers.provider.send("evm_mine", []);
      expect(
        locker.unlock(lockId)
      ).to.be.revertedWith('Before endTime');

      // increase timestamp
      await ethers.provider.send("evm_increaseTime", [100]);
      await ethers.provider.send("evm_mine", []);

      let lockInfoAfter = await locker.locks(lockId);
      // console.log(lockInfoAfter);
      expect(lockInfoAfter.amount).to.equal(0);

      // unlock
      let unlockTx = await locker.unlock(lockId);
      let unlockReceipt = await unlockTx.wait();
      let OnUnlock = unlockReceipt.logs.find(event => event.fragment?.name == "OnUnlock");
      const [, , owner, amount] = OnUnlock.args;
      expect(owner).to.equal(signer.address);
      expect(lockInfoBefore.amount).to.equal(lockInfoAfter.unlockedAmount);
    }),
      it("test vesting lp", async function () {
      const { factory, tokenA, tokenB, pair, locker, signer, feeTo, user1 } = await init();
      // set approval
      await pair.approve(locker.target, ethers.MaxUint256);
      // endTime(tgeTime)
      let currentBlock = await getCurrentBlock();
      let endTime = currentBlock.timestamp + 200;
      let lockAmount = BigNumber(1e20).toFixed(0);
      let params = {
        token: pair.target,
        tgeBps: 2000, // 20 %
        cycleBps: 2000, // 20% per cycle
        owner: user1.address,
        amount: lockAmount,
        tgeTime: endTime,
        cycle: 100
      }
      // lock and get lockId from event
      let tx = await locker.vestingLock(params, "LP_ONLY");
      const receipt = await tx.wait();
      let logs = receipt.logs.find(event => event.fragment?.name == "OnLock");
      const [lockId] = logs.args;
      let lockInfoBefore = await locker.locks(lockId);
      // console.log(lockInfoBefore);
      expect(lockInfoBefore.unlockedAmount).to.equal(0);

      // increase timestamp
      await ethers.provider.send("evm_increaseTime", [200]);
      await ethers.provider.send("evm_mine", []);

      await locker.connect(user1).unlock(lockId);
      let lockInfo = await locker.locks(lockId);
      expect(lockInfo.unlockedAmount).to.be.not.equal(0);
      await expect(await pair.balanceOf(user1.address)).to.equal(lockInfo.unlockedAmount);

      // increase 200 will unlock 2 cycle = 40 % 
      await ethers.provider.send("evm_increaseTime", [200]);
      await ethers.provider.send("evm_mine", []);

      // unlock
      await locker.connect(user1).unlock(lockId);
      let lockInfoAfter = await locker.locks(lockId);
      expect(lockInfoAfter.unlockedAmount).to.greaterThan(lockInfo.unlockedAmount);

      // increase 200 will unlock 2 cycle = 40 % , unlock all
      await ethers.provider.send("evm_increaseTime", [200]);
      await ethers.provider.send("evm_mine", []);
      // unlock
      await locker.connect(user1).unlock(lockId);
      lockInfoAfter = await locker.locks(lockId);
      expect(lockInfoAfter.unlockedAmount).to.equal(lockInfoBefore.amount);
      // Nothing to unlock
      await ethers.provider.send("evm_increaseTime", [200]);
      await ethers.provider.send("evm_mine", []);
      // unlock
      await  expect(
          locker.connect(user1).unlock(lockId)
      ).to.be.revertedWith("Nothing to unlock");
    })
  })
});
