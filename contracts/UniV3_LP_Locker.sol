// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interface/INonfungiblePositionManager.sol";
import "./interface/IUniswapV3Factory.sol";
import "./libs/TransferHelper.sol";

contract UniV3_LP_Locker is IERC721Receiver, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.UintSet;

    struct FeeStruct {
        string name; // name by which the fee is accessed
        uint256 lpFee; // 100 = 1%, 10,000 = 100%
        uint256 collectFee; // 100 = 1%, 10,000 = 100%
        uint256 lockFee; // in amount tokens
        address lockFeeToken; // address(0) = ETH otherwise ERC20 address expected
    }

    struct LockInfo {
        uint256 lockId;
        INonfungiblePositionManager nftPositionManager;
        address pendingOwner;
        address owner;
        address collector;
        address collectAddress; // receive collections when not specified 
        address pool;
        uint256 collectFee;
        uint256 nftId;
        uint256 startTime;
        uint256 endTime;
    }

    // contains keccak(feeName)
    EnumerableSet.Bytes32Set private _feeNameHashSet; 
    // fees
    mapping(bytes32 nameHash => FeeStruct) public _fees;
    address public _feeReceiver;
    address public _customFeeSigner;

    uint256 constant public FEE_DENOMINATOR = 10_000;

    uint256 public _nextLockId = 1;

    // 支持的 nftPositionManger 列表
    EnumerableSet.AddressSet private _nftManagers;

    // 锁仓详情
    mapping(uint256 lockId => LockInfo) public _locks;

    // 用户的锁仓
    mapping(address => EnumerableSet.UintSet) private _userLocks;

    event OnLock(
        uint256 indexed lockId,
        address nftPositionManager,
        address owner,
        uint256 nftId,
        uint256 endTime
    );
    event OnUnlock(
        uint256 indexed lockId,
        address owner,
        uint256 nftId,
        uint256 unlockedTime
    );
    event OnLockPendingTransfer(
        uint256 indexed lockId,
        address previousOwner,
        address newOwner
    );
    event OnLockTransferred(
        uint256 indexed lockId,
        address previousOwner,
        address newOwner
    );
    event OnIncreaseLiquidity(uint256 indexed lockId);
    event OnDecreaseLiquidity(uint256 indexed lockId);
    event onRelock(uint256 indexed lockId, uint256 endTime);
    event OnSetCollector(uint256 indexed lockId, address collector);
    event OnAddFee(bytes32 nameHash, string name, uint256 lpFee, uint256 collectFee, uint256 lockFee, address lockFeeToken);
    event OnEditFee(bytes32 nameHash, string name, uint256 lpFee, uint256 collectFee, uint256 lockFee, address lockFeeToken);
    event onRemoveFee(bytes32 nameHash);


    modifier validLockOwner(uint256 lockId) {
        require(lockId < _nextLockId, "Invalid lockId");
        require(_locks[lockId].owner == _msgSender(), "Not lock owner");
        _;
    }

    constructor(
        address nftManager_,
        address feeReceiver_,
        address customFeeSigner_
    ) Ownable(_msgSender()) {
        _nftManagers.add(nftManager_);
        _feeReceiver = feeReceiver_;
        _customFeeSigner = customFeeSigner_;
        addOrUpdateFee("DEFAULT", 50, 200, 0, address(0));
        addOrUpdateFee("LVP", 80, 100, 0, address(0));
        addOrUpdateFee("LLP", 30, 350, 0, address(0));
    }

    function addOrUpdateFee(string memory name_, uint256 lpFee_, uint256 collectFee_, uint256 lockFee_, address lockFeeToken_) public onlyOwner {
        bytes32 nameHash = keccak256(abi.encodePacked(name_));

        FeeStruct memory feeObj = FeeStruct(name_, lpFee_, collectFee_, lockFee_, lockFeeToken_);
        _fees[nameHash] = feeObj;
        if(_feeNameHashSet.contains(nameHash)) {
            emit OnEditFee(nameHash, name_, lpFee_, collectFee_, lockFee_, lockFeeToken_);
        } else {
            _feeNameHashSet.add(nameHash);
            emit OnAddFee(nameHash, name_, lpFee_, collectFee_, lockFee_, lockFeeToken_);
        }
    }

    function removeFee(string memory name_) external onlyOwner {
        bytes32 nameHash = keccak256(abi.encodePacked(name_));
        require(nameHash != keccak256(abi.encodePacked("DEFAULT")), "DEFAULT");
        require(_feeNameHashSet.contains(nameHash), "Fee not exists");
        _feeNameHashSet.remove(nameHash);
        delete _fees[nameHash];
        emit onRemoveFee(nameHash);
    }

    function updateFeeReceiver(address feeReceiver_) external onlyOwner {
        _feeReceiver = feeReceiver_;
    }

    function updateFeeSigner(address feeSigner_) external onlyOwner {
        _customFeeSigner = feeSigner_;
    }

    function addSupportedNftManager(address nftManager_) external onlyOwner {
        _nftManagers.add(nftManager_);
    }

    function supportedNftManager(
        address nftManager_
    ) public view returns (bool) {
        return _nftManagers.contains(nftManager_);
    }

    function isSupportedFeeName(string memory name_) public view returns(bool) {
        bytes32 nameHash = keccak256(abi.encodePacked(name_));
        return _feeNameHashSet.contains(nameHash);
    }

    function getFee (string memory _name) public view returns (FeeStruct memory) {
        bytes32 feeHash = keccak256(abi.encodePacked(_name));
        require(_feeNameHashSet.contains(feeHash), "NOT FOUND");
        return _fees[feeHash];
    }

    function _deductLockFee(FeeStruct memory feeObj) internal {
        if(feeObj.lockFeeToken == address(0)) {// ETH
            require(msg.value == feeObj.lockFee, "Insufficient Fee");
            TransferHelper.safeTransferETH(_feeReceiver, msg.value);
        } else {
            TransferHelper.safeTransferFrom(feeObj.lockFeeToken, _msgSender(), _feeReceiver, feeObj.lockFee);
        }
    }

    function _getPool(INonfungiblePositionManager nftManager_, uint256 nftId_) internal view returns(address pool) {
         (,, address token0, address token1, uint24 fee,,,,,,,) = nftManager_.positions(nftId_);
        // get factory
        IUniswapV3Factory factory = IUniswapV3Factory(nftManager_.factory());
        // get pool
        pool = factory.getPool(token0, token1, fee);

    }

    function lock(
        INonfungiblePositionManager nftManager_,
        uint256 nftId_,
        address owner_,
        address collector_,
        address collectAddress_,
        uint256 endTime_,
        string memory  feeName_
    ) external payable returns (uint256 lockId) {
        require(collector_ != address(0), "CollectAddress invalid");
        require(endTime_ > block.timestamp, "EndTime <= currentTime");
        require(isSupportedFeeName(feeName_), "FeeName invalid");
        require(
            supportedNftManager(address(nftManager_)),
            "nftPositionManager not supported"
        );
        FeeStruct memory feeObj = getFee(feeName_);
        lockId = _lock(nftManager_, nftId_, owner_, collector_, collectAddress_, endTime_, feeObj);
    }

    function lockWithCustomFee(
        INonfungiblePositionManager nftManager_,
        uint256 nftId_,
        address owner_,
        address collector_,
        address collectAddress_,
        uint256 endTime_,
        bytes memory signature_,
        FeeStruct memory feeObj_
    ) external payable returns (uint256 lockId) {
        require(collector_ != address(0), "CollectAddress invalid");
        require(endTime_ > block.timestamp, "EndTime <= currentTime");
        require(
            supportedNftManager(address(nftManager_)),
            "nftPositionManager not supported"
        );
        _verifySignature(feeObj_, signature_);
        lockId = _lock(nftManager_, nftId_, owner_, collector_, collectAddress_, endTime_, feeObj_);
    }

    function _verifySignature(
        FeeStruct memory fee,
        bytes memory signature
    ) internal view {
        bytes32 messageHash = keccak256(abi.encodePacked(fee.name, fee.lpFee, fee.collectFee, fee.lockFee, fee.lockFeeToken));
        bytes32 prefixedHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address signer = ECDSA.recover(prefixedHash, signature);
        require(signer == _customFeeSigner, "FeeSigner not allowed");
    }

    function _lock(
        INonfungiblePositionManager nftManager_,
        uint256 nftId_,
        address owner_,
        address collector_,
        address collectAddress_,
        uint256 endTime_,
        FeeStruct memory feeObj
    ) internal returns (uint256 lockId) {
        if(feeObj.lockFee > 0) {
            _deductLockFee(feeObj);
        }

        nftManager_.safeTransferFrom(_msgSender(), address(this), nftId_);
        address pool = _getPool(nftManager_, nftId_);
       
        // collect fees for user to prevent being charged a fee on existing fees
        nftManager_.collect(INonfungiblePositionManager.CollectParams(nftId_, owner_, type(uint128).max, type(uint128).max));

        // Take lp fee
        if (feeObj.lpFee > 0) {
            uint128 liquidity = _getLiquidity(nftManager_, nftId_);
            nftManager_.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams(nftId_, uint128(liquidity * feeObj.lpFee / FEE_DENOMINATOR),
                0, 0, block.timestamp));
            nftManager_.collect(INonfungiblePositionManager.CollectParams(nftId_, _feeReceiver, type(uint128).max, type(uint128).max));
        }

        LockInfo memory newLock = LockInfo({
            lockId: _nextLockId,
            nftPositionManager: nftManager_,
            pendingOwner: address(0),
            owner: owner_,
            collector: collector_,
            collectAddress: collectAddress_,
            pool: pool,
            collectFee: feeObj.collectFee,
            nftId: nftId_,
            startTime: block.timestamp,
            endTime: endTime_
        });
        _locks[newLock.lockId] = newLock;
        _userLocks[owner_].add(newLock.lockId);
        _nextLockId++;

        emit OnLock(
            newLock.lockId,
            address(nftManager_),
            owner_,
            nftId_,
            endTime_
        );
        return newLock.lockId;
    }

    function transferLock(
        uint256 lockId_,
        address newOwner_
    ) external validLockOwner(lockId_) {
        _locks[lockId_].pendingOwner = newOwner_;
        emit OnLockPendingTransfer(lockId_, _msgSender(), newOwner_);
    }

    function acceptLock(uint256 lockId_) external {
        require(lockId_ < _nextLockId, "Invalid lockId");
        address newOwner = _msgSender();
        // check new owner
        require(newOwner == _locks[lockId_].pendingOwner, "Not pendingOwner");
        // emit event
        emit OnLockTransferred(lockId_, _locks[lockId_].owner, newOwner);
        // remove lockId from owner
        _userLocks[_locks[lockId_].owner].remove(lockId_);
        // add lockId to new owner
        _userLocks[newOwner].add(lockId_);
        // set owner
        _locks[lockId_].pendingOwner = address(0);
        _locks[lockId_].owner = newOwner;
    }

    /**
     * @dev increases liquidity. Can be called by anyone.
     */
    function increaseLiquidity(
        uint256 lockId_,
        INonfungiblePositionManager.IncreaseLiquidityParams calldata params
    )
        external
        payable
        nonReentrant
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        LockInfo memory userLock = _locks[lockId_];
        require(userLock.nftId == params.tokenId, "Invalid NFT_ID");

        (, , address token0, address token1, , , , , , , , ) = userLock
            .nftPositionManager
            .positions(userLock.nftId);

        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        TransferHelper.safeTransferFrom(
            token0,
            _msgSender(),
            address(this),
            params.amount0Desired
        );
        TransferHelper.safeTransferFrom(
            token1,
            _msgSender(),
            address(this),
            params.amount1Desired
        );
        TransferHelper.safeApprove(
            token0,
            address(userLock.nftPositionManager),
            params.amount0Desired
        );
        TransferHelper.safeApprove(
            token1,
            address(userLock.nftPositionManager),
            params.amount1Desired
        );

        (liquidity, amount0, amount1) = userLock
            .nftPositionManager
            .increaseLiquidity(params);

        uint256 balance0diff = IERC20(token0).balanceOf(address(this)) - balance0Before;
        uint256 balance1diff = IERC20(token1).balanceOf(address(this)) - balance1Before;
        if (balance0diff > 0) {
            TransferHelper.safeTransfer(token0, _msgSender(), balance0diff);
        }
        if (balance1diff > 0) {
            TransferHelper.safeTransfer(token1, _msgSender(), balance1diff);
        }

        emit OnIncreaseLiquidity(lockId_);
    }

    /**
     * @dev decrease liquidity if a lock has expired
     */
    function decreaseLiquidity(
        uint256 lockId_,
        INonfungiblePositionManager.DecreaseLiquidityParams calldata params
    )
        external
        payable
        validLockOwner(lockId_)
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        LockInfo memory userLock = _locks[lockId_];
        require(userLock.nftId == params.tokenId, "Invalid NFT_ID");
        require(userLock.endTime < block.timestamp, "NOT YET");
        _collect(lockId_, _msgSender(), type(uint128).max, type(uint128).max); // collect protocol fees
        (amount0, amount1) = userLock.nftPositionManager.decreaseLiquidity(params);
        userLock.nftPositionManager.collect(
            INonfungiblePositionManager.CollectParams(
                userLock.nftId,
                _msgSender(),
                type(uint128).max,
                type(uint128).max
            )
        );
        emit OnDecreaseLiquidity(lockId_);
    }

    function unlock(uint256 lockId_) external validLockOwner(lockId_) {
        LockInfo memory userLock = _locks[lockId_];
        require(userLock.endTime < block.timestamp, "Not yet");

        _collect(lockId_, userLock.owner, type(uint128).max, type(uint128).max);

        userLock.nftPositionManager.safeTransferFrom(
            address(this),
            userLock.owner,
            userLock.nftId
        );
        _userLocks[userLock.owner].remove(lockId_);

        emit OnUnlock(lockId_, userLock.owner, userLock.nftId, block.timestamp);

        delete _locks[lockId_]; // clear the state for this lock (reset all values to zero)
    }

    function relock(
        uint256 lockId_,
        uint256 endTime_
    ) external validLockOwner(lockId_) nonReentrant {
        LockInfo storage userLock = _locks[lockId_];
        require(endTime_ > userLock.endTime, "EndTime <= currentEndTiem");
        require(endTime_ > block.timestamp, "EndTime <= now");
        userLock.endTime = endTime_;
        emit onRelock(lockId_, userLock.endTime);
    }

    /**
     * @dev Private collect function, wrap this in re-entrancy guard calls
     */
    function _collect(
        uint256 lockId_,
        address recipient_,
        uint128 amount0Max_,
        uint128 amount1Max_
    ) private returns (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1) {
        LockInfo memory userLock = _locks[lockId_];
        require(
            userLock.owner == _msgSender() || userLock.collector == _msgSender(),
            "Not owner"
        );
        if(userLock.collectFee == 0) {
            // No user collect fee
            (amount0, amount1) = userLock.nftPositionManager.collect(
                INonfungiblePositionManager.CollectParams(
                    userLock.nftId,
                    recipient_,
                    amount0Max_,
                    amount1Max_
                )
            );
        } else {
            (,,address _token0,address _token1,,,,,,,,) = userLock.nftPositionManager.positions(userLock.nftId);
            uint256 balance0 = IERC20(_token0).balanceOf(address(this));
            uint256 balance1 = IERC20(_token1).balanceOf(address(this));

            userLock.nftPositionManager.collect(
                INonfungiblePositionManager.CollectParams(userLock.nftId, address(this), amount0Max_, amount1Max_)
            );

            balance0 = IERC20(_token0).balanceOf(address(this)) - balance0;
            balance1 = IERC20(_token1).balanceOf(address(this)) - balance1;
            if(balance0 > 0) {
                fee0 = balance0 * userLock.collectFee / FEE_DENOMINATOR;
                TransferHelper.safeTransfer(_token0, _feeReceiver, fee0);
                amount0 = balance0 - fee0;
                TransferHelper.safeTransfer(_token0, recipient_, amount0);
            }
            if(balance1 > 0) {
                fee1 = balance1 * userLock.collectFee / FEE_DENOMINATOR;
                TransferHelper.safeTransfer(_token1, _feeReceiver, fee1);
                amount1 = balance1 - fee1;
                TransferHelper.safeTransfer(_token1, recipient_, amount1);
            }
        }
    }

    /**
     * @dev Collect fees to _recipient if msg.sender is the owner of _lockId
     */
    function collect(
        uint256 lockId_,
        address recipient_,
        uint128 amount0Max_,
        uint128 amount1Max_
    )
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1, uint256 fee0, uint256 fee1)
    {
        (amount0, amount1, fee0, fee1) = _collect(
            lockId_,
            recipient_,
            amount0Max_,
            amount1Max_
        );
    }

    /**
     * @dev set the adress to which fees are automatically collected
     */
    function setCollectAddress(
        uint256 lockId_,
        address collector_
    ) external validLockOwner(lockId_) nonReentrant {
        require(collector_ != address(0), "COLLECT_ADDR");
        LockInfo storage userLock = _locks[lockId_];
        userLock.collector = collector_;
        emit OnSetCollector(lockId_, collector_);
    }

    /**
    * @dev returns just the liquidity value from a position
    */
    function _getLiquidity (INonfungiblePositionManager _nftPositionManager, uint256 _tokenId) private view returns (uint128) {
        (,,,,,,,uint128 liquidity,,,,) = _nftPositionManager.positions(_tokenId);
        return liquidity;
    }

    /**
    * @dev Allows admin to remove any eth mistakenly sent to the contract
    */
    function adminRefundEth (uint256 _amount, address payable _receiver) external onlyOwner nonReentrant {
        (bool success, ) = _receiver.call{value: _amount}("");
        if (!success) {
            revert("Gas token transfer failed");
        }
    }

    /**
    * @dev Allows admin to remove any ERC20's mistakenly sent to the contract
    * Since this contract is only for locking NFT liquidity, this allows removal of ERC20 tokens and cannot remove locked NFT liquidity.
    */
    function adminRefundERC20 (address _token, address _receiver, uint256 _amount) external onlyOwner nonReentrant {
        // TransferHelper.safeTransfer = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        // Attempting to transfer nfts with this function (substituting a nft_id for _amount) wil fail with 'ST' as NFTS do not have the same interface
        TransferHelper.safeTransfer(_token, _receiver, _amount);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        operator;
        from;
        tokenId;
        data;
        return IERC721Receiver.onERC721Received.selector;
    }
}
