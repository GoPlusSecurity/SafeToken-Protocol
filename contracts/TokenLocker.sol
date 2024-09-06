// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interface/IUniswapV2Factory.sol";
import "./interface/IUniswapV2Pair.sol";
import "./interface/ITokenLocker.sol";

import "./libs/TransferHelper.sol";
import "./libs/FullMath.sol";
import "./libs/SafeUniswapCall.sol";

contract TokenLocker is ITokenLocker, SafeUniswapCall, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // 当前 lockId
    uint256 public _nextLockId = 1;

    // 锁仓详情
    mapping(uint256 lockId => LockInfo) public _locks;

    // 用户的锁仓
    mapping(address => EnumerableSet.UintSet) private _userNormalLocks;
    mapping(address => EnumerableSet.UintSet) private _userLpLocks;

    // token 对应的锁仓
    mapping(address => EnumerableSet.UintSet) private _tokenLocks;

    // token 锁仓统计数据
    mapping(address => CumulativeLockInfo) public cumulativeInfos;

    // 
    uint256 constant DENOMINATOR = 10_000;

    // contains keccak(feeName)
    EnumerableSet.Bytes32Set private _feeNameHashSet; 
    EnumerableSet.Bytes32Set private _tokenSupportedFeeNames; 
    EnumerableSet.Bytes32Set private _lpSupportedFeeNames; 
    // fees
    mapping(bytes32 nameHash => FeeStruct) public _fees;
    address public _feeReceiver;
    
    modifier validLockOwner(uint256 lockId_) {
        require(lockId_ < _nextLockId, "Invalid lockId");
        require(_locks[lockId_].owner == _msgSender(), "Not lock owner");
        _;
    }

    constructor(address feeReceiver_) Ownable(_msgSender()) {
        _feeReceiver = feeReceiver_;
        addOrUpdateFee("TOKEN", 0, 12 * 10 ** 16, address(0), false);
        addOrUpdateFee("LP_ONLY", 50, 0, address(0), true);
        addOrUpdateFee("LP_AND_ETH", 25, 6 * 10 ** 16, address(0), true);
    }

    function addOrUpdateFee(string memory name_, uint256 lpFee_, uint256 lockFee_, address lockFeeToken_, bool isLp) public onlyOwner {
        bytes32 nameHash = keccak256(abi.encodePacked(name_));

        FeeStruct memory feeObj = FeeStruct(name_, lpFee_, lockFee_, lockFeeToken_);
        _fees[nameHash] = feeObj;
        if(_feeNameHashSet.contains(nameHash)) {
            emit OnEditFee(nameHash, name_, lpFee_, lockFee_, lockFeeToken_);
        } else {
            _feeNameHashSet.add(nameHash);
            emit OnAddFee(nameHash, name_, lpFee_, lockFee_, lockFeeToken_);
        }
        if(isLp) {
            _lpSupportedFeeNames.add(nameHash);
        } else {
            _tokenSupportedFeeNames.add(nameHash);
        }
    }

    function updateFeeReceiver(address feeReceiver_) external onlyOwner {
        _feeReceiver = feeReceiver_;
        emit FeeReceiverUpdated(feeReceiver_);
    }

    function _takeFee(address token_, uint256 amount, string memory feeName_) internal returns (bool isLpToken, uint256 newAmount){
        isLpToken = checkIsPair(token_);
        bytes32 nameHash = keccak256(abi.encodePacked(feeName_));
        if(isLpToken) {
            require(_lpSupportedFeeNames.contains(nameHash), "FeeName not supported for lpToken");
        }else {
            require(_tokenSupportedFeeNames.contains(nameHash), "FeeName not supported for Token");
        }
        newAmount = amount;
        FeeStruct memory feeObj = _fees[nameHash];
        if(isLpToken && feeObj.lpFee > 0) {
            uint256 lpFeeAmount = amount * feeObj.lpFee / DENOMINATOR;
            newAmount = amount - lpFeeAmount;
            IUniswapV2Pair(token_).transfer(token_, lpFeeAmount);
            IUniswapV2Pair(token_).burn(_feeReceiver);
        }
        if(feeObj.lockFee > 0) {
            if(feeObj.lockFeeToken == address(0)) {
                require(msg.value == feeObj.lockFee, "Fee");
                TransferHelper.safeTransferETH(_feeReceiver, msg.value);
            } else {
                TransferHelper.safeTransferFrom(feeObj.lockFeeToken, _msgSender(), _feeReceiver, feeObj.lockFee);
            }
        }
    }

    function _addLock(
        address token_,
        bool isLpToken_,
        address owner_,
        uint256 amount_,
        uint256 endTime_,
        uint256 cycle_,
        uint24 tgeBps_,
        uint24 cycleBps_
    ) internal returns (uint256 lockId) {
        lockId = _nextLockId;
        _locks[lockId] = LockInfo({
            lockId: lockId,
            token: token_,
            isLpToken: isLpToken_,
            pendingOwner: address(0),
            owner: owner_,
            amount: amount_,
            startTime: block.timestamp,
            endTime: endTime_,
            cycle: cycle_,
            tgeBps: tgeBps_,
            cycleBps: cycleBps_,
            unlockedAmount: 0
        });
        _nextLockId++;
    }

    /**
     * @dev should called in lock or lockWithPermit method
     */
    function _createLock( 
        address token_,
        string memory feeName_,
        address owner_,
        uint256 amount_,
        uint256 endTime_
    ) internal returns (uint256 lockId) {
        TransferHelper.safeTransferFrom(
            token_,
            _msgSender(),
            address(this),
            amount_
        );
        (bool isLpToken_, uint256 newAmount) = _takeFee(token_, amount_, feeName_);
        lockId = _addLock(token_, isLpToken_, owner_, newAmount, endTime_, 0, 0, 0);
        if(isLpToken_) {
            _userLpLocks[owner_].add(lockId);
        } else {
            _userNormalLocks[owner_].add(lockId);
        }
        _tokenLocks[token_].add(lockId);
        cumulativeInfos[token_].amount += newAmount;
        emit OnLock(lockId, token_, owner_, newAmount, endTime_);
    }

    function lock(
        address token_,
        string memory feeName_,
        address owner_,
        uint256 amount_,
        uint256 endTime_
    ) external payable override nonReentrant returns (uint256 lockId) {
        require(token_ != address(0), "Invalid token");
        require(endTime_ > block.timestamp, "EndTime <= currentTime");
        require(amount_ > 0, "Amount is 0");
        
        lockId = _createLock(token_, feeName_, owner_, amount_, endTime_);
    }

    function lockWithPermit(
        address token_,
        string memory feeName_,
        address owner_,
        uint256 amount_,
        uint256 endTime_,
        uint256 deadline_,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable override nonReentrant returns (uint256 lockId) {
        require(token_ != address(0), "Invalid token");
        require(endTime_ > block.timestamp, "EndTime <= currentTime");
        require(amount_ > 0, "Amount is 0");
        IERC20Permit(token_).permit(_msgSender(), address(this), amount_, deadline_, v, r, s);
        lockId = _createLock(token_, feeName_, owner_, amount_, endTime_);
    }

    function _vestingLock(VestingLockParams memory params, string memory feeName_) internal returns (uint256 lockId) {
        require(params.tgeTime > block.timestamp, "tgeTime <= currentTime");
        require(params.cycle > 0, "Invalid cycle");
        require(
            params.tgeBps > 0 && params.cycleBps > 0 
                && params.tgeBps + params.cycleBps <= DENOMINATOR, 
            "Invalid bips"
        );
        TransferHelper.safeTransferFrom(
            params.token,
            _msgSender(),
            address(this),
            params.amount
        );
        (bool isLpToken, uint256 newAmount) = _takeFee(params.token, params.amount, feeName_);
        lockId = _addLock(
            params.token,
            isLpToken,
            params.owner,
            newAmount,
            params.tgeTime,
            params.cycle,
            params.tgeBps,
            params.cycleBps
        );
        if(isLpToken) {
            _userLpLocks[params.owner].add(lockId);
        } else {
            _userNormalLocks[params.owner].add(lockId);
        }
        _tokenLocks[params.token].add(lockId);
        cumulativeInfos[params.token].amount += newAmount;
        emit OnLock(lockId, params.token, params.owner, newAmount, params.tgeTime);
    }

    function vestingLock(
        VestingLockParams memory params,
        string memory feeName_
    ) external payable override nonReentrant returns (uint256 lockId) {
        require(params.token != address(0), "Invalid token");
        require(params.amount > 0, "Amount is 0");
        lockId = _vestingLock(params, feeName_);
    }

    function vestingLockWithPermit(
        VestingLockParams memory params,
        string memory feeName_,
        uint256 deadline_,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable override nonReentrant returns (uint256 lockId) {
        require(params.token != address(0), "Invalid token");
        require(params.amount > 0, "Amount is 0");
        IERC20Permit(params.token).permit(_msgSender(), address(this), params.amount, deadline_, v, r, s);
        lockId = _vestingLock(params, feeName_);
    }

    function _updateLock(
        uint256 lockId_,
        uint256 moreAmount_,
        uint256 newEndTime_ 
    ) internal {
        require(
            newEndTime_ > _locks[lockId_].endTime && newEndTime_ > block.timestamp,
            "NewEndTime not allowed"
        );
        address lockOwner = _msgSender();
        TransferHelper.safeTransferFrom(
            _locks[lockId_].token,
            lockOwner,
            address(this),
            moreAmount_
        );
        _locks[lockId_].amount += moreAmount_;
        _locks[lockId_].endTime = newEndTime_;
        cumulativeInfos[_locks[lockId_].token].amount += moreAmount_;
        emit OnUpdated(
            lockId_,
            _locks[lockId_].token,
            lockOwner,
            _locks[lockId_].amount,
            newEndTime_
        );
    }

    /**
     * @param lockId_  lockId in _tokenLocks
     * @param moreAmount_  the amount to increase
     * @param newEndTime_  new endtime must gt old
     */
    function updateLock(
        uint256 lockId_,
        uint256 moreAmount_,
        uint256 newEndTime_
    ) external override validLockOwner(lockId_) nonReentrant {
        require(moreAmount_ > 0, "MoreAmount is 0");
        _updateLock(lockId_, moreAmount_, newEndTime_);
    }

    function updateLockWitPermit(
        uint256 lockId_,
        uint256 moreAmount_,
        uint256 newEndTime_,
        uint256 deadline_,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override validLockOwner(lockId_) nonReentrant {
        require(moreAmount_ > 0, "MoreAmount is 0");
        IERC20Permit(_locks[lockId_].token).permit(_msgSender(), address(this), moreAmount_, deadline_, v, r, s);
        _updateLock(lockId_, moreAmount_, newEndTime_);
    }

    function transferLock(
        uint256 lockId_,
        address newOwner_
    ) external override validLockOwner(lockId_) {
        _locks[lockId_].pendingOwner = newOwner_;
        emit OnLockPendingTransfer(lockId_, _msgSender(), newOwner_);
    }

    function acceptLock(uint256 lockId_) external override {
        require(lockId_ < _nextLockId, "Invalid lockId");
        address newOwner = _msgSender();
        // check new owner
        require(newOwner == _locks[lockId_].pendingOwner, "Not pendingOwner");
        // emit event
        emit OnLockTransferred(lockId_, _locks[lockId_].owner, newOwner);

        if(_locks[lockId_].isLpToken) {
            _userLpLocks[_locks[lockId_].owner].remove(lockId_);
            _userLpLocks[newOwner].add(lockId_);
        } else {
            // remove lockId from owner
            _userNormalLocks[_locks[lockId_].owner].remove(lockId_);
            // add lockId to new Owner
            _userNormalLocks[newOwner].add(lockId_);
        }
        // set owner
        _locks[lockId_].pendingOwner = address(0);
        _locks[lockId_].owner = newOwner;
    }

    function unlock(
        uint256 lockId_
    ) external override validLockOwner(lockId_) nonReentrant {
        LockInfo storage lockInfo = _locks[lockId_];
        require(lockInfo.owner == _msgSender(), "Not owner");
        if (lockInfo.tgeBps > 0) {
            _vestingUnlock(lockInfo);
        } else {
            _normalUnlock(lockInfo);
        }
    }

    function _normalUnlock(LockInfo storage lockInfo) internal {
        require(block.timestamp > lockInfo.endTime, "Before endTime");
        if(lockInfo.isLpToken) {
            _userLpLocks[lockInfo.owner].remove(lockInfo.lockId);
        } else {
            _userNormalLocks[lockInfo.owner].remove(lockInfo.lockId);
        }
        _tokenLocks[lockInfo.token].remove(lockInfo.lockId);
        TransferHelper.safeTransfer(
            lockInfo.token,
            lockInfo.owner,
            lockInfo.amount
        );
        cumulativeInfos[lockInfo.token].amount -= lockInfo.amount;
        emit OnUnlock(
            lockInfo.lockId,
            lockInfo.token,
            lockInfo.owner,
            lockInfo.amount,
            block.timestamp
        );
        lockInfo.amount = 0;
    }

    function _vestingUnlock(LockInfo storage lockInfo) internal {
        uint256 withdrawable = _withdrawableTokens(lockInfo);
        uint256 newTotalUnlockAmount = lockInfo.unlockedAmount + withdrawable;
        require(
            withdrawable > 0 && newTotalUnlockAmount <= lockInfo.amount,
            "Nothing to unlock"
        );
        if (newTotalUnlockAmount == lockInfo.amount) {
            _tokenLocks[lockInfo.token].remove(lockInfo.lockId);
            if(lockInfo.isLpToken) {
                _userLpLocks[lockInfo.owner].remove(lockInfo.lockId);
            } else {
                _userNormalLocks[lockInfo.owner].remove(lockInfo.lockId);
            }
            emit OnUnlock(
                lockInfo.lockId,
                lockInfo.token,
                msg.sender,
                newTotalUnlockAmount,
                block.timestamp
            );
        }
        lockInfo.unlockedAmount = newTotalUnlockAmount;

        TransferHelper.safeTransfer(
            lockInfo.token,
            lockInfo.owner,
            withdrawable
        );
        cumulativeInfos[lockInfo.token].amount -= withdrawable;
        emit OnLockVested(
            lockInfo.lockId,
            lockInfo.token,
            _msgSender(),
            withdrawable,
            lockInfo.amount - lockInfo.unlockedAmount,
            block.timestamp
        );
    }

    function _withdrawableTokens(
        LockInfo memory userLock
    ) internal view returns (uint256) {
        if (userLock.amount == 0) return 0;
        if (userLock.unlockedAmount >= userLock.amount) return 0;
        if (block.timestamp < userLock.endTime) return 0;
        if (userLock.cycle == 0) return 0;

        uint256 tgeReleaseAmount = FullMath.mulDiv(
            userLock.amount,
            userLock.tgeBps,
            DENOMINATOR
        );
        uint256 cycleReleaseAmount = FullMath.mulDiv(
            userLock.amount,
            userLock.cycleBps,
            DENOMINATOR
        );
        uint256 currentTotal = 0;
        if (block.timestamp >= userLock.endTime) {
            currentTotal =
                (((block.timestamp - userLock.endTime) / userLock.cycle) *
                    cycleReleaseAmount) +
                tgeReleaseAmount;
        }
        uint256 withdrawable = 0;
        if (currentTotal > userLock.amount) {
            withdrawable = userLock.amount - userLock.unlockedAmount;
        } else {
            withdrawable = currentTotal - userLock.unlockedAmount;
        }
        return withdrawable;
    }

    function withdrawableTokens(
        uint256 lockId_
    ) external override view returns (uint256) {
        LockInfo memory userLock = _locks[lockId_];
        return _withdrawableTokens(userLock);
    }

    function userNormalLocks(
        address user
    ) external view returns (uint256[] memory lockIds) {
        return _userNormalLocks[user].values();
    }

    function userLpLocks(
        address user
    ) external view returns (uint256[] memory lockIds) {
        return _userLpLocks[user].values();
    }

    function tokenLocks(
        address token
    ) external view returns (uint256[] memory lockIds) {
        return _tokenLocks[token].values();
    }

    function supportedTokenFees() external view returns(bytes32[] memory hashes) {
        return _tokenSupportedFeeNames.values();
    }

    function supportedLpFees() external view returns(bytes32[] memory hashes) {
        return _lpSupportedFeeNames.values();
    }

}
