// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TimeTickBaseDepot is ReentrancyGuard, Ownable, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Constants
    uint256 public constant STAKE_UNIT = 3600 ether;     // 1 stake = 3600 TTB
    uint256 public constant UNSTAKE_DELAY = 3 days;
    uint256 public constant RENEWAL_PERIOD = 180 days;
    uint256 public constant BATCH_SIZE = 500;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant DEV_SHARE = 30;   
    uint256 private constant STAKER_SHARE = 70;

    // Core contract references
    IERC20 public immutable ttbToken;
    address public immutable devFundAddress;

    // Distribution tracking
    uint256 public currentRewardPerShare;
    uint256 public lastProcessedIndex;

    // Staking state
    struct Staker {
        uint256 stakedAmount;
        uint256 unclaimedRewards;
        uint256 lastRenewalTime;
        uint256 unstakeTime;
    }
    
    mapping(address => Staker) public stakers;
    uint256 public totalStaked;
    uint256 public minimumStake;
    EnumerableSet.AddressSet private stakerSet;

    // Control flags
    bool public stakingEnabled;
    bool public rewardsEnabled;

    // Events
    event RewardsReceived(uint256 totalAmount, uint256 devShare, uint256 rewardPerShare);
    event BatchProcessed(uint256 startIndex, uint256 endIndex, uint256 rewardPerShare);
    event StakeReceived(address indexed staker, uint256 amount);
    event UnstakeRequested(address indexed staker, uint256 amount);
    event UnstakeCompleted(address indexed staker, uint256 amount);
    event UnstakeCancelled(address indexed staker);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event StakeRenewed(address indexed staker);
    event MinimumStakeUpdated(uint256 newMinimum);
    event StakingToggled(bool enabled);
    event RewardsToggled(bool enabled);
    event ContractPaused(address indexed by);
    event ContractUnpaused(address indexed by);

    constructor(
        address _ttbToken,
        address _devFundAddress
    ) Ownable(msg.sender) {
        require(_ttbToken != address(0), "Invalid token address");
        require(_devFundAddress != address(0), "Invalid dev fund address");
        
        ttbToken = IERC20(_ttbToken);
        devFundAddress = _devFundAddress;
        minimumStake = STAKE_UNIT;
        
        stakingEnabled = false;
        rewardsEnabled = false;
    }

    // Admin functions
    function toggleStaking() external onlyOwner {
        stakingEnabled = !stakingEnabled;
        emit StakingToggled(stakingEnabled);
    }
    
    function toggleRewards() external onlyOwner {
        rewardsEnabled = !rewardsEnabled;
        emit RewardsToggled(rewardsEnabled);
    }

    function setMinimumStake(uint256 _newMinimum) external onlyOwner {
        require(_newMinimum >= STAKE_UNIT, "Below stake unit");
        require(_newMinimum % STAKE_UNIT == 0, "Must be whole units");
        minimumStake = _newMinimum;
        emit MinimumStakeUpdated(_newMinimum);
    }

    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }
    
    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }

    // Core distribution functions
    function processNewMint() external nonReentrant whenNotPaused {
        require(rewardsEnabled, "Rewards not enabled");
        require(totalStaked > 0, "No stakers");
        
        // Get new tokens
        uint256 newTokens = ttbToken.balanceOf(address(this));
        require(newTokens > 0, "No new tokens");
        
        // Process dev share
        uint256 devRewards = (newTokens * DEV_SHARE) / 100;
        require(ttbToken.transfer(devFundAddress, devRewards), "Dev transfer failed");
        
        // Calculate reward per share
        uint256 stakerShare = newTokens - devRewards;
        currentRewardPerShare = (stakerShare * PRECISION) / totalStaked;
        lastProcessedIndex = 0; // Reset for new distribution
        
        emit RewardsReceived(newTokens, devRewards, currentRewardPerShare);
    }

    function processRewardBatch() external nonReentrant whenNotPaused {
        require(currentRewardPerShare > 0, "No rewards to process");
        
        uint256 stakerCount = stakerSet.length();
        require(lastProcessedIndex < stakerCount, "All stakers processed");
        
        uint256 endIndex = Math.min(lastProcessedIndex + BATCH_SIZE, stakerCount);
        address[] memory currentStakers = stakerSet.values();
        
        // Process batch
        for (uint256 i = lastProcessedIndex; i < endIndex; i++) {
            address stakerAddr = currentStakers[i];
            Staker storage staker = stakers[stakerAddr];
            
            if (staker.stakedAmount > 0) {
                uint256 reward = (staker.stakedAmount * currentRewardPerShare) / PRECISION;
                staker.unclaimedRewards += reward;
            }
        }
        
        lastProcessedIndex = endIndex;
        if (lastProcessedIndex >= stakerCount) {
            currentRewardPerShare = 0; // Reset after full distribution
        }
        
        emit BatchProcessed(lastProcessedIndex, endIndex, currentRewardPerShare);
    }

    // Staking functions
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(stakingEnabled, "Staking not enabled");
        require(amount >= minimumStake, "Below minimum stake");
        require(amount % STAKE_UNIT == 0, "Must stake whole units");
        
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime == 0, "Unstake pending");
        
        // Transfer tokens from user
        require(ttbToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Update stake
        staker.stakedAmount += amount;
        staker.lastRenewalTime = block.timestamp;
        totalStaked += amount;
        
        // Add to staker set if new
        if (!stakerSet.contains(msg.sender)) {
            stakerSet.add(msg.sender);
        }
        
        emit StakeReceived(msg.sender, amount);
    }
    
    function requestUnstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount > 0, "No stake found");
        require(staker.unstakeTime == 0, "Unstake already pending");
        
        staker.unstakeTime = block.timestamp + UNSTAKE_DELAY;
        
        emit UnstakeRequested(msg.sender, staker.stakedAmount);
    }
    
    function cancelUnstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime > 0, "No unstake request");
        require(staker.stakedAmount > 0, "No stake found");
        
        staker.unstakeTime = 0;
    }
    
    function unstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime > 0 && block.timestamp >= staker.unstakeTime, "Not ready");
        require(staker.stakedAmount > 0, "No stake found");
        
        uint256 amount = staker.stakedAmount;
        uint256 rewards = staker.unclaimedRewards;
        
        // Clear stake
        totalStaked -= amount;
        staker.stakedAmount = 0;
        staker.unclaimedRewards = 0;
        staker.unstakeTime = 0;
        staker.lastRenewalTime = 0;
        
        // Remove from staker set
        stakerSet.remove(msg.sender);
        
        // Transfer tokens and rewards
        if (rewards > 0) {
            require(ttbToken.transfer(msg.sender, rewards), "Rewards transfer failed");
            emit RewardsClaimed(msg.sender, rewards);
        }
        require(ttbToken.transfer(msg.sender, amount), "Stake transfer failed");
        
        emit UnstakeCompleted(msg.sender, amount);
    }
    
    function renewStake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount > 0, "No stake found");
        require(block.timestamp <= staker.lastRenewalTime + RENEWAL_PERIOD, "Stake expired");
        
        // Process any pending rewards
        if (staker.unclaimedRewards > 0) {
            uint256 rewards = staker.unclaimedRewards;
            staker.unclaimedRewards = 0;
            require(ttbToken.transfer(msg.sender, rewards), "Transfer failed");
            emit RewardsClaimed(msg.sender, rewards);
        }
        
        staker.lastRenewalTime = block.timestamp;
        emit StakeRenewed(msg.sender);
    }
    
    function claimRewards() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unclaimedRewards > 0, "No rewards to claim");
        
        uint256 rewards = staker.unclaimedRewards;
        staker.unclaimedRewards = 0;
        require(ttbToken.transfer(msg.sender, rewards), "Transfer failed");
        
        emit RewardsClaimed(msg.sender, rewards);
    }

    function getStakerInfo(address staker) external view returns (
        uint256 stakedAmount,
        uint256 unclaimedRewards,
        uint256 lastRenewalTime,
        uint256 unstakeTime
    ) {
        Staker storage s = stakers[staker];
        return (s.stakedAmount, s.unclaimedRewards, s.lastRenewalTime, s.unstakeTime);
    }

    function getNetworkStats() external view returns (
        uint256 totalStakedAmount,
        uint256 totalStakers,
        uint256 currentReward,
        uint256 minimumStakeRequired
    ) {
        return (
            totalStaked,
            stakerSet.length(),
            currentRewardPerShare,
            minimumStake
        );
    }
}