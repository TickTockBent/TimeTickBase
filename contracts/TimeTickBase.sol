// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract TimeToken is ERC20, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Core state
    uint256 public immutable genesisTime;
    uint256 public lastMintTime;
    uint256 public constant STAKE_UNIT = 3600 ether;  // 1 stake = 3600 TTB
    uint256 public constant UNSTAKE_DELAY = 3 days;
    uint256 public constant RENEWAL_PERIOD = 180 days;
    uint256 private constant PRECISION = 1e18;
    
    // Distribution constants
    uint8 private constant DEV_SHARE = 30;      // 30%
    uint8 private constant STAKER_SHARE = 70;   // 70%
    
    // Staking state
    struct Staker {
        uint256 stakedAmount;          // Amount of TTB staked
        uint256 unclaimedRewards;      // Pending rewards
        uint256 lastRenewalTime;       // Last renewal timestamp
        uint256 unstakeTime;           // When tokens can be unstaked (0 if no pending unstake)
    }
    
    mapping(address => Staker) public stakers;
    uint256 public totalStaked;
    uint256 public minimumStake;
    address public immutable devFundAddress;

    // Staker tracking
    EnumerableSet.AddressSet private stakerSet;
    
    // Events
    event Staked(address indexed staker, uint256 amount);
    event UnstakeRequested(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event StakeRenewed(address indexed staker);
    event StakeExpired(address indexed staker, uint256 amount, uint256 rewards);
    event RewardsProcessed(uint256 totalRewards, uint256 devShare, uint256 stakerShare);
    
    constructor(address _devFundAddress) ERC20("TimeToken", "TTB") {
        require(_devFundAddress != address(0), "Invalid dev fund address");
        devFundAddress = _devFundAddress;
        genesisTime = block.timestamp;
        lastMintTime = block.timestamp;
        minimumStake = STAKE_UNIT;  // Start with 1 stake minimum
    }
    
    // Staking
    function stake(uint256 amount) external nonReentrant {
        require(amount >= minimumStake, "Below minimum stake");
        require(amount % STAKE_UNIT == 0, "Must stake whole units");
        
        // Check and process any expired stakes before adding new ones
        _processExpiredStakes();
        
        // Transfer tokens to contract
        require(transfer(address(this), amount), "Transfer failed");
        
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime == 0, "Unstake pending");
        
        // Update stake
        staker.stakedAmount += amount;
        staker.lastRenewalTime = block.timestamp;
        totalStaked += amount;
        
        // Add to staker set if new staker
        if (staker.stakedAmount == amount) { // Previously zero
            stakerSet.add(msg.sender);
        }
        
        emit Staked(msg.sender, amount);
    }
    
    // Request unstake
    function requestUnstake(uint256 amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount >= amount, "Insufficient stake");
        require(staker.unstakeTime == 0, "Unstake already pending");
        require(amount % STAKE_UNIT == 0, "Must unstake whole units");
        
        staker.unstakeTime = block.timestamp + UNSTAKE_DELAY;
        
        emit UnstakeRequested(msg.sender, amount);
    }
    
    // Complete unstake after delay
    function unstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime > 0 && block.timestamp >= staker.unstakeTime, "Not ready");
        
        uint256 amount = staker.stakedAmount;
        
        // Clear stake
        totalStaked -= amount;
        staker.stakedAmount = 0;
        staker.unstakeTime = 0;
        staker.lastRenewalTime = 0;
        
        // Remove from staker set
        stakerSet.remove(msg.sender);
        
        // Force claim any pending rewards
        if (staker.unclaimedRewards > 0) {
            uint256 rewards = staker.unclaimedRewards;
            staker.unclaimedRewards = 0;
            require(transfer(msg.sender, rewards), "Reward transfer failed");
            emit RewardsClaimed(msg.sender, rewards);
        }
        
        // Return staked tokens
        require(transfer(msg.sender, amount), "Stake transfer failed");
        
        emit Unstaked(msg.sender, amount);
    }
    
    // Renew stake
    function renewStake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount > 0, "No stake found");
        require(block.timestamp <= staker.lastRenewalTime + RENEWAL_PERIOD, "Stake expired");
        
        // Force claim rewards on renewal
        if (staker.unclaimedRewards > 0) {
            uint256 rewards = staker.unclaimedRewards;
            staker.unclaimedRewards = 0;
            require(transfer(msg.sender, rewards), "Reward transfer failed");
            emit RewardsClaimed(msg.sender, rewards);
        }
        
        staker.lastRenewalTime = block.timestamp;
        emit StakeRenewed(msg.sender);
    }
    
    // Claim rewards
    function claimRewards() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unclaimedRewards > 0, "No rewards to claim");
        
        uint256 rewards = staker.unclaimedRewards;
        staker.unclaimedRewards = 0;
        require(transfer(msg.sender, rewards), "Transfer failed");
        
        emit RewardsClaimed(msg.sender, rewards);
    }
    
    // Process any expired stakes
    function _processExpiredStakes() internal {
        if (stakerSet.length() == 0) return;
        
        address[] memory _stakers = stakerSet.values();
        
        for (uint256 i = 0; i < _stakers.length; i++) {
            address stakerAddr = _stakers[i];
            Staker storage staker = stakers[stakerAddr];
            
            if (staker.stakedAmount > 0 && 
                block.timestamp > staker.lastRenewalTime + RENEWAL_PERIOD) {
                
                uint256 amount = staker.stakedAmount;
                uint256 rewards = staker.unclaimedRewards;
                
                // Clear stake
                totalStaked -= amount;
                staker.stakedAmount = 0;
                staker.unclaimedRewards = 0;
                staker.lastRenewalTime = 0;
                
                // Remove from staker set
                stakerSet.remove(stakerAddr);
                
                // Return tokens (stake + rewards)
                require(transfer(stakerAddr, amount + rewards), "Transfer failed");
                
                emit StakeExpired(stakerAddr, amount, rewards);
            }
        }
    }
    
    // Daily validation and reward distribution
    function processRewardsAndValidation() external nonReentrant {
        require(block.timestamp >= lastMintTime + 1 days, "Too soon");
        
        // First process any expired stakes
        _processExpiredStakes();
        
        // Calculate tokens to mint
        uint256 elapsedTime = block.timestamp - lastMintTime;
        uint256 tokensToMint = elapsedTime * 1 ether; // 1 token per second
        
        // Mint new tokens to this contract
        _mint(address(this), tokensToMint);
        
        // Calculate shares
        uint256 devRewards = (tokensToMint * DEV_SHARE) / 100;
        uint256 stakerRewards = tokensToMint - devRewards;
        
        // Send dev share
        require(transfer(devFundAddress, devRewards), "Dev transfer failed");
        
        // Distribute staker share if there are stakers
        if (totalStaked > 0) {
            address[] memory _stakers = stakerSet.values();
            for (uint256 i = 0; i < _stakers.length; i++) {
                address stakerAddr = _stakers[i];
                Staker storage staker = stakers[stakerAddr];
                
                if (staker.stakedAmount > 0) {
                    // Calculate proportion first to maintain precision
                    uint256 proportion = (staker.stakedAmount * PRECISION) / totalStaked;
                    uint256 share = (stakerRewards * proportion) / PRECISION;
                    staker.unclaimedRewards += share;
                }
            }
        }
        
        lastMintTime = block.timestamp;
        
        emit RewardsProcessed(tokensToMint, devRewards, stakerRewards);
    }
    
    // Helper function to get all stakers
    function _getStakers() internal view returns (address[] memory) {
        return stakerSet.values();
    }
}