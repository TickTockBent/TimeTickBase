// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract TimeTickBase is ERC20, ReentrancyGuard {

    // Some people asked why I named it TimeTickBase
    // It's because it has the same initials as my username, TTB
    // That's the main reason
    // But also it's a time-based token
    // And TickBase sounds cool
    // Also TickBase means 'reference time unit'
    // And I like the sound of that
    // So I combined them
    // TimeTickBase > TTB
    // I'm not very creative with names, sorry
    // But I hope you like it anyway
    // - TTB

    using EnumerableSet for EnumerableSet.AddressSet;

    // Core state
    // Genesis time is when the contract was deployed
    // Last mint time is when the last reward was processed
    // Stake unit is the amount of TTB required to stake
    // Unstake delay is the time required to wait before unstaking
    // Renewal period is the time required to renew a stake
    // Precision is used for calculations (might be overkill)
    // I'll think about it later
    // - TTB

    uint256 public immutable genesisTime;
    uint256 public lastMintTime;
    uint256 public constant STAKE_UNIT = 3600 ether;  // 1 stake = 3600 TTB
    uint256 public constant UNSTAKE_DELAY = 3 days;
    uint256 public constant RENEWAL_PERIOD = 180 days;
    uint256 private constant PRECISION = 1e18;
    
    // Distribution constants
    // Dev share is the percentage of rewards going to the dev fund
    // Staker share is the percentage of rewards going to stakers
    // The sum of both should be 100%
    // This is probably obvious but I'm explaining it anyway
    // - TTB

    // Change uint8 to uint256 for consistency and gas optimization
    // Also, I like to be explicit with types
    // It's a good habit, I think
    // - TTB

    uint256 private constant DEV_SHARE = 30;   
    uint256 private constant STAKER_SHARE = 70;

    // Add validation for PRECISION
    // This is to ensure the precision is valid
    // I like to be safe with these things, as I said
    // It's probably overkill again
    // But I like it, so I'm keeping it
    // - TTB

    function _validatePrecision() internal pure {
        require(PRECISION > 0, "Invalid precision");
    }
    
    // Staker struct
    // Stakers are tracked by address
    // Stakers have a staked amount
    // Stakers have unclaimed rewards
    // Stakers have a last renewal time
    // Stakers have an unstake time
    // Stakers are stored in a set for easy tracking
    // - TTB

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
    // I like events, they're fun
    // And they're useful for debugging
    // And for tracking contract activity
    // So I added a bunch of events
    // I hope you like them
    // - TTB

    event Staked(address indexed staker, uint256 amount);
    event UnstakeRequested(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event StakeRenewed(address indexed staker);
    event StakeExpired(address indexed staker, uint256 amount, uint256 rewards);
    event TimeValidation(int256 correctionFactor);
    event RewardsProcessed(uint256 totalRewards, uint256 devShare, uint256 stakerShare, int256 correctionFactor, bool validated);
    event UnstakeCancelled(address indexed staker, uint256 amount);

    constructor(address _devFundAddress) ERC20("TimeTickBase", "TTB") {
        require(_devFundAddress != address(0), "Invalid dev fund address");
        devFundAddress = _devFundAddress;
        genesisTime = block.timestamp;
        lastMintTime = block.timestamp;
        minimumStake = STAKE_UNIT;  // Start with 1 stake minimum
    }
    
    // Staking functions
    // Staking requires a minimum amount of TTB
    // Staking is done in whole units of STAKE_UNIT
    // Staking is subject to unstake delay and renewal period
    // Staking rewards are processed periodically
    // Staking rewards are minted to the contract
    // Staking rewards are claimed by stakers and distributed to dev fund
    // Staking rewards are distributed to stakers based on their share of total staked
    // So claim your rewards regularly to keep the rewards flowing
    // - TTB

    function stake(uint256 amount) external nonReentrant {
        require(amount >= minimumStake, "Below minimum stake");
        require(amount % STAKE_UNIT == 0, "Must stake whole units");
        
        // Check and process any expired stakes before adding new ones
        // This is to prevent dead stakes
        // And to clean up the staker set
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
    // Unstake is subject to delay
    // IDK why you'd want to unstake but it's here if you need it
    // Maybe you need the tokens for something else
    // Or maybe you're just tired of staking
    // Or maybe you're just testing the contract
    // Whatever the reason, it's your choice
    // - TTB

    // Turns out using transfer instead of _transfer makes a difference
    // By leaving off the _ I was trying to transfer tokens from the user's wallet on unstake
    // Which is obviously not what I want
    // I want to transfer tokens from the contract back to the user
    // So I need to use _transfer instead of transfer
    // I'm glad I caught that before deploying
    // - TTB

    function requestUnstake(uint256 amount) external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount >= amount, "Insufficient stake");
        require(staker.unstakeTime == 0, "Unstake already pending");
        require(amount % STAKE_UNIT == 0, "Must unstake whole units");
        
        staker.unstakeTime = block.timestamp + UNSTAKE_DELAY;
        
        emit UnstakeRequested(msg.sender, amount);
    }
    
    // Complete unstake after delay
    // Unstake is only allowed after the delay period
    // Unstake returns staked tokens and pending rewards
    // The delay is to prevent abuse
    // Maybe I should add a cancel unstake function
    // But I'm not sure if it's necessary
    // I'll think about it
    // - TTB

    function unstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime > 0 && block.timestamp >= staker.unstakeTime, "Not ready");
        
        uint256 amount = staker.stakedAmount;
        
        // Clear stake
        // This removes the entire stake
        // And will then return the tokens
        // It will also remove the staker from the staker set
        // and force claim any pending rewards
        // I will probably let people partially unstake in the future
        // So long as it doesn't bring them below the minimum stake
        // But for now, it's all or nothing
        // - TTB

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
            _transfer(address(this), msg.sender, rewards);
            emit RewardsClaimed(msg.sender, rewards);
        }
        
        // Return staked tokens
        _transfer(address(this), msg.sender, amount);
        
        emit Unstaked(msg.sender, amount);
    }
    
    // Cancel unstake request
    // This is to prevent unstake if you change your mind
    // Or if you accidentally requested unstake
    // I thought about it and decided to add this function
    // It's a good way to prevent mistakes
    // And to keep the contract clean
    // - TTB

    function cancelUnstake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeTime > 0, "No unstake request");
        require(staker.stakedAmount > 0, "No stake found");
        
        // Reset unstake time
        staker.unstakeTime = 0;
        
        emit UnstakeCancelled(msg.sender, staker.stakedAmount);
    }

    // Renew stake
    // Stakers can renew their stake before it expires
    // This is to prevent dead stakes
    // And to keep the rewards flowing to active stakers
    // Rewards are claimed on renewal to keep things simple
    // And keep the contract accounting clean
    // - TTB

    function renewStake() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.stakedAmount > 0, "No stake found");
        require(block.timestamp <= staker.lastRenewalTime + RENEWAL_PERIOD, "Stake expired");
        
        // Force claim rewards on renewal
        if (staker.unclaimedRewards > 0) {
            uint256 rewards = staker.unclaimedRewards;
            staker.unclaimedRewards = 0;
            _transfer(address(this), msg.sender, rewards);
            emit RewardsClaimed(msg.sender, rewards);
        }
        
        staker.lastRenewalTime = block.timestamp;
        emit StakeRenewed(msg.sender);
    }
    
    // Claim rewards
    // Rewards are claimed separately from staking
    // This is to keep the contract clean and simple
    // And to prevent any issues with staking
    // Rewards are minted to the contract periodically
    // Rewards are claimed to the staker's address

    function claimRewards() external nonReentrant {
        Staker storage staker = stakers[msg.sender];
        require(staker.unclaimedRewards > 0, "No rewards to claim");
        
        uint256 rewards = staker.unclaimedRewards;
        staker.unclaimedRewards = 0;
        _transfer(address(this), msg.sender, rewards);
        
        emit RewardsClaimed(msg.sender, rewards);
    }
    
    // Process any expired stakes
    // This is done before any reward processing
    // Expired stakes are returned to stakers
    // This is mostly here to prevent dead stakes
    // Proof of life, if you will
    // It's also a good way to clean up the staker set

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
                _transfer(address(this), stakerAddr, amount + rewards);
                
                emit StakeExpired(stakerAddr, amount, rewards);
            }
        }
    }
    
    // Regular reward processing - public interface
    // This is called by anyone to process rewards
    // I decided to leave this public
    // So anyone can call it if they want to
    // It's a public service, if you will
    // And it's a good way to keep the rewards flowing
    // You can spam it, but you'll just waste gas
    // So don't do that, it's not nice
    // - TTB

    function processRewards() external {
        _processRewardsAndValidation(0);
    }
    
    // Internal implementation
    function _processRewardsAndValidation(int256 correctionFactor) internal nonReentrant {
        require(block.timestamp > lastMintTime, "Already processed");
        
        // First process any expired stakes
        _processExpiredStakes();
        
        // Calculate tokens to mint
        uint256 elapsedTime = block.timestamp - lastMintTime;
        uint256 tokensToMint = elapsedTime * 1 ether; // 1 token per second
        
        // Apply correction if any  
        if (correctionFactor > 0) {
            tokensToMint += uint256(correctionFactor);
        } else if (correctionFactor < 0) {
            tokensToMint -= uint256(-correctionFactor);
        }
        
        // Mint new tokens to this contract
        _mint(address(this), tokensToMint);
        
        // Calculate shares
        uint256 devRewards = (tokensToMint * DEV_SHARE) / 100;
        uint256 stakerRewards = tokensToMint - devRewards;
        
        // Distribute staker share if there are stakers
        // 70% go to stakers, 30% go to dev fund
        // This is the default distribution
        // If there are no stakers, all rewards go to dev fund
        // But there should always be stakers
        // Except at genesis, but that's a special case
        // - TTB
        
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
        } else {
            // If no stakers, add staker share to dev rewards
            devRewards += stakerRewards;
        }

        // Send dev share (30% if stakers exist, 100% if no stakers)
        // Dev fund gets full emissions if no stakers
        // This is mostly to fund the genesis fountain
        // There should never be no stakers, except at genesis
        // But this will catch any edge cases as well
        // - TTB

        _transfer(address(this), devFundAddress, devRewards);
        
        lastMintTime = block.timestamp;
        
        emit RewardsProcessed(tokensToMint, devRewards, stakerRewards, correctionFactor, correctionFactor != 0);
    }

    function validateTotalTime() external nonReentrant returns (int256) {
        uint256 totalElapsedTime = block.timestamp - genesisTime;
        uint256 expectedSupply = totalElapsedTime * 1 ether;
        uint256 currentSupply = totalSupply();
        
        int256 correction = int256(expectedSupply) - int256(currentSupply);
        
        // Limit maximum positive correction to 1 hour of tokens
        if (correction > int256(3600 ether)) {
            correction = int256(3600 ether);
        }
        
        // Ensure correction won't result in negative emissions
        if (correction < 0) {
            uint256 elapsedTime = block.timestamp - lastMintTime;
            uint256 expectedEmission = elapsedTime * 1 ether;
            if (uint256(-correction) > expectedEmission) {
                correction = -int256(expectedEmission);
            }
        }
        
        if (correction != 0) {
            emit TimeValidation(correction);
            _processRewardsAndValidation(correction);
        }
        
        return correction;
    }

    // Why are you still reading this?
    // Go stake some TTB and earn rewards
    // Or go build something cool, that's the point of this
    // I'm just here to help you get started
    // - TTB

    // P.S. I'm not a financial advisor
    // This is not financial advice
    // I'm just a developer who likes to build stuff
    // So please don't sue me if you lose money
    // I'm not responsible for your decisions
    // You're a grown-up, you can make your own choices
    // - TTB

    // P.P.S. If you have any questions, feel free to ask
    // I'm happy to help if I can
    // contact@timetickbase.com
    // - TTB

    // P.P.P.S. I'm not planning to die
    // I'm just saying you never know
    // - TTB

    // P.P.P.P.S. I'm not planning to hand this off to anyone either
    // I'm just saying you never know
    // - TTB    

    // P.P.P.P.P.S. You're still reading this?
    // Seriously, go do something else
    // But thanks for reading this far
    // I appreciate it
    // Here's a cookie for you 🍪
    // And an ascii cat
    //  /\_/\
    // ( o.o ) meow
    //  > ^ <
    // - TTB

    // These functions gets all the staker info
    // It will be used for the front-end
    // So people can see their staking status
    // And claim rewards
    // And renew stakes
    // And all that good stuff
    // - TTB

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
        uint256 rewardRate,  // Will be 1 ether (1e18) per second
        uint256 minimumStakeRequired
    ) {
        return (
            totalStaked,
            stakerSet.length(),
            1 ether,
            minimumStake
        );
    }

    // Helper function to get all stakers
    function _getStakers() internal view returns (address[] memory) {
        return stakerSet.values();
    }

    // Really though, go do something else
    // I'm just rambling at this point
    // I just finished the first draft of this contract
    // And I'm feeling a bit loopy
    // But I'm happy with how it turned out
    // And I'm excited to test it
    // - TTB 01/07/2025
}