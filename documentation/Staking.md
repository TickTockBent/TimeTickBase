# TimeTickBase Staking System Specification

## Overview

The TimeTickBase (TTB) staking system implements a straightforward staking mechanism where users can stake TTB tokens to participate in reward distribution. The system maintains simplicity while providing necessary protections against gaming attempts.

## Core Concepts

### Basic Units
- One stake unit = 3,600 TTB
- Stakes must be complete units (no fractional stakes)
- Minimum stake requirement varies by phase

### Staking Process
- Stake requests process immediately
- Unstaking requires 3-day delay
- One active unstake request per address
- Rewards continue during unstake delay

### Renewal Requirement
- Stakes must be renewed every 6 months
- Serves as proof-of-life mechanism
- No penalty for renewal beyond timeframe
- Non-renewed stakes automatically returned
- Accumulated rewards remain claimable

## Technical Implementation

### Core State Storage
```solidity
struct Staker {
    uint256 currentStakes;           // Current stake units
    uint256 lastRenewalTimestamp;    // Last time stake was renewed
    StateChange pendingChange;       // Single pending state change
}

struct StateChange {
    uint256 amount;         // Amount to change
    uint256 requestTime;    // When request was made
    uint256 processTime;    // When change can be processed
    ChangeType changeType;  // Type of change (add/remove)
}

mapping(address => Staker) public stakers;
uint256 public totalNetworkStakes;
```

### Reward Distribution
- Occurs during batch minting operations
- Based on current stake proportions
- 70% of emissions to stakers
- Proportional to stake amount vs total network stakes

### Safety Mechanisms
- 3-day unstaking delay prevents gaming
- Minimum stake requirements
- Single pending change per address
- Automatic stake return if not renewed
- Emergency pause capabilities

## Examples

### Basic Staking
```
Starting State:
- Network: 10,000 total stakes
- Alice: 1,000 stakes (10%)
- Bob: 2,000 stakes (20%)
- Charlie: 7,000 stakes (70%)

During batch mint:
- Total rewards = 86,400 TTB (1 day of emissions)
- Staker portion = 60,480 TTB (70%)
- Alice receives: 6,048 TTB (10%)
- Bob receives: 12,096 TTB (20%)
- Charlie receives: 42,336 TTB (70%)
```

### Unstaking Example
```
1. Bob requests to unstake 1,000 stakes at T
2. Request creates state change with processTime = T + 3 days
3. Stake continues earning rewards normally
4. At T + 3 days, stake reduces by 1,000
5. Tokens return to Bob's wallet
```

## Security Considerations

### State Management
- Clear state change system
- Atomic operations
- Proper overflow protection
- Gas optimization

### Unstaking Protection
- Fixed 3-day delay provides market stability
- Single pending change prevents manipulation
- Continued rewards during delay maintain fairness
- Clear unstake status tracking

### Stake Renewal
- Required every 6 months
- User-initiated confirmation
- Automatic unstaking if not renewed
- Clear warning system as deadline approaches

### Risk Mitigations
- Minimum stake requirements
- Rate limiting on stake changes
- Emergency pause capabilities
- Proper access controls

## Interface Requirements

### Core Display Elements
- Current stakes and proportional share
- Estimated daily rewards
- Network total stakes
- Next batch mint estimate
- Processing status for stake changes
- Clear renewal deadlines

### User Settings
- Notification preferences
- Auto-renewal options (optional)
- Reward claim preferences
- Alert configurations

### Monitoring
- Network stake changes
- Total staker count
- Historical reward data
- Basic network statistics

This specification provides the foundation for implementing the TTB staking system while maintaining simplicity and security. The system prioritizes predictability and fairness while implementing necessary protections against manipulation.