// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TimeToken is ERC20, ReentrancyGuard {
    // Timing / Emission state
    uint256 public lastMintTime;
    uint256 public genesisTime;
    uint256 public batchDuration;

    // Distribution constants
    uint8 private constant NO_KEEPERS_DEV_SHARE = 100;
    uint8 private constant WITH_KEEPERS_DEV_SHARE = 30;
    uint8 private constant WITH_KEEPERS_VALIDATORS_SHARE = 70;
    uint256 private constant PERCENT_BASE = 100;

    // Fund address
    address public immutable devFundAddress;
    uint256 public devFundTotal;

    // Staking state
    mapping(address => uint256) public currentStakes;     // Stake units (3600 TTB each)
    mapping(address => uint256) public accruedStakeHours; // Proportional hours accumulated
    mapping(address => uint256) public stakeStartTime;
    uint256 public totalNetworkStakes;

    // Staker tracking with efficient removal
    mapping(address => uint256) private stakerIndices;  // Maps address to array index + 1
    address[] private stakers;

    // Stake change tracking
    enum ChangeType {
        NONE,
        STAKE_ADD,
        STAKE_REMOVE
    }

    struct StateChange {
        uint256 amount;
        uint256 requestTime;
        uint256 processTime;
        ChangeType changeType;
    }

    struct HourBoundary {
        uint256 hour;
        bool queued;
    }

    mapping(address => StateChange) public pendingChanges;
    HourBoundary public nextBoundary;

    // Constants
    uint256 public constant STAKE_UNIT = 3600 ether;
    uint256 public constant UNSTAKE_DELAY = 3 days;
    uint256 public minimumStakeUnits;
    bool public globalStakeLock; // Stub for future implementation

    // Events remain the same

    constructor(address _devFundAddress, uint256 _batchDuration) ERC20("TimeToken", "TTB") {
        require(_devFundAddress != address(0), "Invalid dev fund address");
        require(_batchDuration > 0, "Batch duration must be positive");

        devFundAddress = _devFundAddress;
        batchDuration = _batchDuration;
        genesisTime = block.timestamp;
        lastMintTime = block.timestamp;
        minimumStakeUnits = 1;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        require(sender != address(0), "Transfer from zero");
        require(recipient != address(0), "Transfer to zero");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "Transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _removeStaker(address staker) internal {
        uint256 index = stakerIndices[staker];
        require(index > 0, "Not a staker");
        index--;

        // Get the last staker
        address lastStaker = stakers[stakers.length - 1];

        if (staker != lastStaker) {
            // Move last staker to the removed position
            stakers[index] = lastStaker;
            stakerIndices[lastStaker] = index + 1;
        }

        stakers.pop();
        delete stakerIndices[staker];
    }

    function _addStaker(address staker) internal {
        if (stakerIndices[staker] == 0) {
            stakers.push(staker);
            stakerIndices[staker] = stakers.length;
        }
    }

    function _queueNextHourBoundary() internal {
        uint256 currentHour = block.timestamp / 3600;
        uint256 currentSecond = block.timestamp % 3600;
        
        uint256 targetHour = currentHour + 
            (currentSecond >= 3570 ? 2 : 1);

        if (!nextBoundary.queued || targetHour > nextBoundary.hour) {
            nextBoundary = HourBoundary(targetHour, true);
        }
    }

    function _processHourBoundary() internal nonReentrant {
        uint256 currentHour = block.timestamp / 3600;
        if (nextBoundary.queued && currentHour >= nextBoundary.hour) {
            // First distribute rewards based on current stakes
            for (uint256 i = 0; i < stakers.length; i++) {
                address staker = stakers[i];
                if (currentStakes[staker] > 0) {
                    accruedStakeHours[staker] += 
                        (currentStakes[staker] * PERCENT_BASE) / totalNetworkStakes;
                }
            }

            // Then process pending changes
            for (uint256 i = 0; i < stakers.length; i++) {
                address staker = stakers[i];
                StateChange memory pending = pendingChanges[staker];

                if (pending.changeType != ChangeType.NONE && block.timestamp >= pending.processTime) {
                    if (pending.changeType == ChangeType.STAKE_ADD) {
                        uint256 stakeUnits = pending.amount / STAKE_UNIT;
                        currentStakes[staker] += stakeUnits;
                        totalNetworkStakes += stakeUnits;
                        _addStaker(staker);
                        stakeStartTime[staker] = block.timestamp;
                        _transfer(staker, address(this), pending.amount);
                    } else {
                        uint256 stakeUnits = pending.amount / STAKE_UNIT;
                        currentStakes[staker] -= stakeUnits;
                        totalNetworkStakes -= stakeUnits;
                        if (currentStakes[staker] == 0) {
                            _removeStaker(staker);
                            stakeStartTime[staker] = 0;
                        }
                        _transfer(address(this), staker, pending.amount);
                    }
                    delete pendingChanges[staker];
                }
            }

            nextBoundary.queued = false;
        }
    }

    function requestStake(uint256 stakeUnits) external {
        require(!globalStakeLock, "Staking locked");
        require(stakeUnits >= minimumStakeUnits, "Below minimum stake");
        require(pendingChanges[msg.sender].changeType == ChangeType.NONE, "Change pending");

        uint256 amount = stakeUnits * STAKE_UNIT;
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _queueNextHourBoundary();
        
        pendingChanges[msg.sender] = StateChange({
            amount: amount,
            requestTime: block.timestamp,
            processTime: block.timestamp + 3600,
            changeType: ChangeType.STAKE_ADD
        });
    }

    function requestUnstake(uint256 stakeUnits) external {
        require(currentStakes[msg.sender] >= stakeUnits, "Insufficient stake");
        require(pendingChanges[msg.sender].changeType == ChangeType.NONE, "Change pending");

        uint256 remainingStake = currentStakes[msg.sender] - stakeUnits;
        require(
            remainingStake >= minimumStakeUnits || remainingStake == 0,
            "Would fall below minimum"
        );

        uint256 amount = stakeUnits * STAKE_UNIT;
        
        _queueNextHourBoundary();

        pendingChanges[msg.sender] = StateChange({
            amount: amount,
            requestTime: block.timestamp,
            processTime: block.timestamp + UNSTAKE_DELAY,
            changeType: ChangeType.STAKE_REMOVE
        });
    }

    // Rest of contract remains the same but add nonReentrant to mint functions
    function mintBatch() external nonReentrant {
        // Same implementation
    }

    function mintBatchValidated() external nonReentrant {
        // Same implementation
    }

    function isValidTimekeeper(address account) public view returns (bool) {
        return currentStakes[account] > 0;
    }

    // getValidTimekeepers can use stakers array directly now
    function getValidTimekeepers() external view returns (address[] memory) {
        uint256 count;
        for (uint256 i = 0; i < stakers.length; i++) {
            if (isValidTimekeeper(stakers[i])) {
                count++;
            }
        }

        address[] memory valid = new address[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < stakers.length; i++) {
            if (isValidTimekeeper(stakers[i])) {
                valid[index] = stakers[i];
                index++;
            }
        }
        return valid;
    }
}