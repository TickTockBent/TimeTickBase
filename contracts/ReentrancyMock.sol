pragma solidity ^0.8.28;

import "./TimeTickBase.sol";

contract ReentrancyMock {
    TimeTickBase public ttb;
    uint8 public attackType;
    bool public attacking;
    
    constructor(address _ttb) {
        ttb = TimeTickBase(_ttb);
    }
    
    // Attack types:
    // 1 = stake
    // 2 = renew
    // 3 = unstake
    // 4 = cancel
    // 5 = claim
    function setAttackType(uint8 _type) external {
        attackType = _type;
    }
    
    function onERC20Received(address, uint256) external returns (bool) {
        if (attacking) {
            if (attackType == 1) ttb.stake(3600 ether);
            if (attackType == 2) ttb.renewStake();
            if (attackType == 3) ttb.unstake();
            if (attackType == 4) ttb.cancelUnstake();
            if (attackType == 5) ttb.claimRewards();
        }
        return true;
    }

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
}