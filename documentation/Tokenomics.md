# TimeTickBase (TTB) Tokenomics
*Version 2.0 – December 2024*

## Token Generation
- Fixed emission rate of 1 TTB per second
- Rewards claimed by Dapp
- Unclaimed rewards released in batched weekly distributions
- Supply increases linearly with time
- No pre-mine or initial allocation
- Supply validation through block timestamps
- Overflow protection and precision handling implemented
- No ability to mint arbitrary tokens

## Distribution Model

### Without Active Stakers
- Development Fund: 100% of emissions
- Inital state prior to activation of Genesis Fountain

### With Active Stakers
- Stakers: 70% of emissions
- Development Fund: 30% of emissions

## Staking Mechanism

### Individual Staking
- Minimum stake: Determined by global variable, expressed in atomic unit (stake-hours)
- Atomic unit: 3,600 TTB (one stake-hour)
- Rewards proportional to maintained stake (1 stake-hour = 1 share)
- Timelock period on stake withdrawals
- Timelock period based on time elapsed since token inception

### Collective Staking
1. On-ramp Aggregator
   - Counts as a single share (one stake-hour)
   - No member stake requirement
   - Rewards split evenly among all members
   - Easy on-ramp for new users to gain tokens, but low rewards
   - An official on-ramp will be maintained by the team after Genesis Fountain ends (faucet)

2. Full-stake Aggregator
   - Pooled stake structure
   - Members transfer stake to leader on join
   - Stake returned to member on exit
   - Reward distribution configured by contract structure
   - Can implement timelock requirements or other requirements/incentives as part of contract

## Genesis Fountain

### Structure
- Duration: 12 months from launch
- Fixed 50 slots
- Stakes a single share (1 stake-hour) which results in an initial 70% network emissions
- Natural dilution as stakers join

### Slot Distribution
- Community Development: 10 slots
- Social Engagement: 10 slots
- Random Selection: 10 slots
- Development Reserve: 10 slots
- Development Funding: 10 slots

### Fountain Timeline
1. First 3 months: Network stake-locked
   - No individual staking allowed
   - No new aggregator contracts accepted
   - Genesis Fountain will be the only share active
2. Month 4-12
   - Genesis Fountain remains 1 stake-hour (1 share)
   - Open staking with natural dilution of fountain rewards as new stakes are placed
   - Minimum stake opens at a high level to prevent immediate dilution of rewards
     - Month 4: 25 stake-hours
     - Month 5: 15 stake-hours
     - Month 6: 10 stake-hours
     - Month 7: 5 stake-hours
     - Month 8: 1 stake-hour
   - After month 8 staking is freely open to anyone with at least 1 stake-hour

## Development Fund
- Dev fund controls TBD

### Usage
- Development costs
- Security audits
- Network infrastructure
- Staff compensation
- User acquisition
- System maintenance
- Quarterly public reporting

## Governance
- Timelord governance requiring large non-earning stake (TODO: Determine what a 'large stake' is)
- Timelords able to create proposals, 4:1 voting share on non-earning stake
- All timekeepers may vote on proposals except emergency
- Multi-signature (3-of-5) requirement
- Variable timelock on withdrawals (non-earning governance stake has longer timelock than earning stakes)