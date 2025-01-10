# TimeTickBase (TTB) Tokenomics
*Version 3.0 – January 2024*

## Token Generation
- Fixed emission rate of 1 TTB per second
- Rewards claimed by dApp, or directly via wallet interaction
- Unclaimed rewards accumulate
- No pre-mine, pre-sale, or initial team allocation
- Token supply starts at zero
- Supply increases linearly with time
- Regular supply validation through block timestamps to avoid drift
- Overflow protection and precision handling implemented
- No ability to mint arbitrary tokens
- No supply manipulation possible

## Distribution Model

### Without Active Stakers
- Development Fund: 100% of emissions
- Inital state prior to activation of Genesis Fountain

### With Active Stakers
- Stakers: 70% of emissions
- Development Fund: 30% of emissions

## Staking Mechanism

### Individual Staking
  - See ./Staking.md

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

### Slot Distribution (This may change depending on grant funding)
- Community Development: 10 slots
  - To be given out for community involvement
- Social Engagement: 10 slots
  - To be given out for marketing and promotion
- Random Selection: 10 slots
  - Random selection from the community, no requirement to enter
- Development Reserve: 10 slots
  - Reserved for code contributions, audit compensation, or other technical assistance
- Company Holding: 10 slots
  - Slots reserved for the company, tokens to be used in future projects

### Fountain Timeline
1. First 3 months: Network stake-locked
   - No individual staking
   - No new aggregator contracts
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
- Multisig controls
- Fixed release of dev fund tokens to cover gas fees
- Fixed release of def fund tokens to cover salaries and expenses
- Governance controls for dev fund token release to cover other situations

### Usage
- Development costs
- Security audits
- Network infrastructure
- Staff compensation
- User acquisition
- System maintenance
- Quarterly public reporting

## Governance
- Timelord governance requiring large non-earning stake
- Timelords able to create proposals, 4:1 voting share on non-earning stake
- All timekeepers may vote on proposals except emergency
- Multi-signature (3-of-5) requirement
- Variable timelock on withdrawals (non-earning governance stake has longer timelock than earning stakes)
- See Governance.md for more details (WIP)