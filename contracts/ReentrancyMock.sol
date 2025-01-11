pragma solidity ^0.8.28;

import "./TimeTickBase.sol";

contract ReentrancyMock {
    TimeTickBase public ttb;
    string public reentryPoint;
    bool public isReentering;
    
    constructor(address _ttb) {
        ttb = TimeTickBase(_ttb);
    }
    
    function setReentryPoint(string memory point) external {
        reentryPoint = point;
    }

    function stake(uint256 amount) external {
        ttb.approve(address(ttb), amount);
        if (isReentering && keccak256(bytes(reentryPoint)) == keccak256(bytes("stake"))) {
            ttb.stake(amount);
        }
        ttb.stake(amount);
    }

    function triggerReentrantStake(uint256 amount) external {
        isReentering = true;
        ttb.stake(amount);
        isReentering = false;
    }

    function triggerReentrantUnstake() external {
        isReentering = true;
        ttb.unstake();
        isReentering = false;
    }

    function triggerReentrantClaim() external {
        isReentering = true;
        ttb.claimRewards();
        isReentering = false;
    }

    // Basic helpers
    function requestUnstake(uint256 amount) external {
        ttb.requestUnstake(amount);
    }
    
    receive() external payable {}
}