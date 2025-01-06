# TimeTickBase Staking System Specification

## Overview

The TimeTickBase (TTB) staking system implements a proportional reward distribution mechanism based on stake-hours. This system maintains the philosophical foundation of time-based tokens while providing an efficient and mathematically sound reward distribution method.

## Core Concepts

### Renewal Requirement
- Stakes must be renewed every 6 months
- Serves as proof-of-life mechanism
- Prevents indefinite reward accumulation by abandoned stakes
- No penalty for renewal beyond timeframe
- Non-renewed stakes are automatically returned
- Accumulated rewards remain claimable

### Stake Units
- Basic unit is one stake (3,600 TTB)
- Represents potential claim on one hour of token generation
- Stakes must be complete units
- Stakes only count after one full hour of existence

### Stake-Hours
- Unit of accumulated reward credit
- Calculated hourly as: (user_stakes / total_network_stakes)
- Accumulates fractionally over time
- One completed stake-hour = 3,600 TTB in rewards
- Tracks proportional network participation over time

### Unstaking Delay
- Fixed delay period between unstaking request and token return
- 3 days (currently)
- Prevents rapid stake cycling and emotional responses to market events
- Natural protection against coordinated unstaking attacks
- One active unstake request per address
- Does not affect reward accumulation during delay period

## Technical Implementation

### Core Contract State Storage

```solidity
enum ChangeType {
    NONE,
    STAKE_ADD,
    STAKE_REMOVE
}

struct StateChange {
    uint256 amount;         // Amount to change
    uint256 requestTime;    // When request was made
    uint256 processTime;    // When change can be processed (immediate for adds, delayed for removes)
    ChangeType changeType;  // Type of change pending
}

struct Staker {
    uint256 currentStakes;           // Current stake units
    uint256 stakedHourAccumulator;   // Accumulated stake-hours
    uint256 lastProcessedHour;       // Last hour accumulator was updated
    uint256 lastRenewalTimestamp;    // Last time stake was renewed
    StateChange pendingChange;       // Single pending state change
}

mapping(address => Staker) public stakers;
uint256 public networkTotalStakes;   // Total valid stakes in network
uint256 public constant UNSTAKE_DELAY = 3 days;
```

Note: Renewal preferences and notifications are handled by a separate management contract to maintain core contract immutability.

### Core Operations

#### Stake Deposit
1. Validate stake amount (multiple of 3,600 TTB)
2. Validate no pending state change
3. Create pending state change:
   - Set amount to stake amount
   - Set requestTime to current time
   - Set processTime to current time
   - Set changeType to STAKE_ADD
4. Transfer TTB to contract
5. Changes process at next hour boundary

#### Stake Withdrawal Request
1. Validate no pending state change
2. Validate stake existence and amount
3. Create pending state change:
   - Set amount to unstake amount
   - Set requestTime to current time
   - Set processTime to current time + UNSTAKE_DELAY
   - Set changeType to STAKE_REMOVE
4. Emit UnstakeRequestedEvent

### Hour Boundary Processing

#### Processing Triggers
Hour boundary processing is initiated by any of the following actions:
- Stake deposit or withdrawal
- Reward claims from stakers
- Development fund reward claims
- Genesis Fountain reward claims

#### Processing Flow
Each trigger initiates the following sequence:
1. Calculate elapsed time and mint tokens since last mint
2. Process any missed hours and update stake-hours
3. Handle pending state changes
   - Update individual stakes
   - Update network total stakes

The system automatically catches up any missed processing periods, ensuring accurate reward distribution regardless of trigger timing.

#### Processing Windows
- Standard Window (XX:00:00 - XX:59:29):
  * State changes queue for next hour boundary
- Boundary Window (XX:59:30 - XX:59:59):
  * State changes automatically queue for hour boundary after next
  * Ensures clean state for processing
  * Prevents race conditions during hour transition

#### Processing Order
1. Calculate stake-hours for current hour:
   - For each staker with valid stakes:
     * Calculate proportion: stakes / networkTotalStakes
     * Add proportion to stakedHourAccumulator
     * Update lastProcessedHour
2. Process pending state changes:
   - For each account with pending change:
     * Validate processTime <= current time
     * Apply change to currentStakes
     * Update networkTotalStakes
     * Clear pending change (set to NONE)
   - Order of processing changes does not affect rewards
     (all changes take effect after hour's stake-hour calculation)

#### Reward Claims
1. Process any pending hours
2. Calculate rewards: stakedHourAccumulator * 3600
3. Zero out stakedHourAccumulator
4. Transfer TTB tokens

### Renewal System

#### Core Mechanics
- 6-month renewal requirement for all stakes
- Renewal is proof-of-life mechanism
- No penalty for renewal beyond required timeframe
- Automatic stake return if renewal missed

#### Stake Return Process
If lastRenewalTimestamp + 6 months < current_time:
1. Transfer full stake amount back to user (currentStakes * 3600 TTB)
2. Accumulated rewards remain claimable
3. Set currentStakes to 0
4. Emit StakeReturnedEvent

#### Renewal Management
- Handled by separate management contract
- Can implement automated renewal systems
- Manages user preferences and notifications
- Upgradeable without affecting core staking mechanics

## Example Scenarios

### Basic Staking
Starting State:
- Network: 10,000 total stakes
- Alice: 1,000 stakes
- Bob: 2,000 stakes
- Charlie: 7,000 stakes

Hour 1:
- Alice accumulates: 1000/10000 = 0.1 stake-hours
- Bob accumulates: 2000/10000 = 0.2 stake-hours
- Charlie accumulates: 7000/10000 = 0.7 stake-hours

Hour 2:
- Same distribution
- Alice total: 0.2 stake-hours
- Bob total: 0.4 stake-hours
- Charlie total: 1.4 stake-hours

Hour 3 (Bob adds 1,000 stakes):
- Network total: 11,000 stakes
- Alice accumulates: 1000/11000 ≈ 0.0909 stake-hours (total 0.2909)
- Bob accumulates: 3000/11000 ≈ 0.2727 stake-hours (total 0.6727)
- Charlie accumulates: 7000/11000 ≈ 0.6363 stake-hours (total 2.0363)

If they claim now:
- Alice receives: 0.2909 * 3600 = 1,047.24 TTB
- Bob receives: 0.6727 * 3600 = 2,421.72 TTB
- Charlie receives: 2.0363 * 3600 = 7,330.68 TTB

### Unstaking Example
1. Bob requests to unstake 1,000 stakes at T
2. Request creates state change with processTime = T + 3 days
3. Stake continues accumulating rewards normally
4. At T + 3 days, after hour evaluation, stake reduces by 1,000
5. Change processes at next hour boundary

## Security Considerations

### Precision Handling
- All calculations must handle decimal precision appropriately
- Accumulator should use fixed-point arithmetic
- Rounding should always favor the protocol

### State Management
- Clear state change system
- Atomic operations for stake changes
- Proper overflow protection
- Gas optimization for batch processing

### Unstaking Protection
- Fixed delay provides market stability
- Single pending change prevents gaming
- Continued rewards during delay maintain fairness
- Clear unstake status tracking

### Stake Renewal System
- Renewal required every 6 months
- User-initiated confirmation of stake maintenance
- Automatic unstaking if not renewed
- Early renewal allowed
- Clear warning system as deadline approaches

### Risk Mitigations
- Maximum stake limit to prevent manipulation
- Rate limiting on stake changes
- Emergency pause capabilities
- Proper access controls
- Automated stake return on missed renewal

## Interface Requirements

### Smart Contract
- Clear view functions for stake status
- Efficient batch processing
- Event emission for all state changes
- Proper error handling and revert messages
- State change inspection functions

### Dapp Interface Requirements

#### Core Display Elements
- Current stakes and proportional network share
- Accumulated stake-hours and estimated rewards
- Network total stakes
- Clear countdown to next hour boundary
- Processing window indicator
  * Standard window: "Changes process next hour"
  * Boundary window: "Changes process in two hours"
- Processing time estimates for all actions

#### Stake Management
- Stake input in both TTB and stake units
- Clear minimum stake requirements
- Pending change status and expected processing time
- Validation before submission
  * Sufficient balance
  * No existing pending changes
  * Meets minimum stake requirement

#### Unstaking Management
- Unstake request interface
- Countdown to unstake processing
- Expected return amount
- Clear warning about 3-day delay
- Option to cancel unprocessed requests

#### Renewal Management
- Time until next required renewal
- Clear renewal countdown
- Early renewal option
- Automated renewal settings
- Warning system
  * 1 month warning
  * 1 week warning
  * 1 day warning
  * Configuration options

#### Network Statistics
- Total network stakes
- Current staker count
- Historical stake charts
- APR estimates based on network share
- Network stake changes (last 24h)

#### Transaction History
- Stake/unstake history
- Reward claim history
- Renewal history
- Filtering and export options

#### User Settings
- Notification preferences
- Display units preference (TTB/stakes)
- Renewal reminder settings
- Auto-compound options

#### Alerts and Notifications
- Hour boundary approaching
- Pending change status updates
- Unstake processing complete
- Renewal requirements
- System status updates

#### Mobile Considerations
- Responsive design for all screens
- Push notification support
- Simplified view options
- Touch-friendly controls

#### Security Features
- Connection status indicator
- Transaction confirmation screens
- Clear warning messages
- Network status monitoring

This interface specification ensures users can effectively interact with all contract features while maintaining a clear understanding of system state and timing.

## Future Considerations

### Scalability
- System naturally handles large user bases efficiently
- Only stores current state
- Low per-user storage requirements
- Efficient batch processing of rewards

### Features
- Automated compounding through management contracts
- Delegation mechanisms
- Team staking integration
- Analytics and reporting

This specification provides the foundation for implementing the TTB staking system while maintaining flexibility for future improvements and optimizations. The core contract remains immutable while allowing extension through separate management contracts.

Note: Need to handle math precision, rounding, remainder, etc