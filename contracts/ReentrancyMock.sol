// Additional functions in ReentrancyMock
function stake(uint256 amount) external {
    ttb.stake(amount);
}

function requestUnstake(uint256 amount) external {
    ttb.requestUnstake(amount);
}

function attackStake() external {
    attacking = true;
    ttb.stake(3600 ether);
    attacking = false;
}

function attackRenew() external {
    attacking = true;
    ttb.renewStake();
    attacking = false;
}

function attackUnstake() external {
    attacking = true;
    ttb.unstake();
    attacking = false;
}

function attackCancel() external {
    attacking = true;
    ttb.cancelUnstake();
    attacking = false;
}

function attackClaim() external {
    attacking = true;
    ttb.claimRewards();
    attacking = false;
}