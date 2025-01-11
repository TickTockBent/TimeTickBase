pragma solidity ^0.8.28;

import "../contracts/TimeTickBase.sol";

contract ReentrancyMock {
    TimeTickBase public ttb;
    
    constructor(address _ttb) {
        ttb = TimeTickBase(_ttb);
    }
    
    // Function that will try to reenter stake
    function attackStake(uint256 amount) external {
        ttb.stake(amount);
    }
    
    // Receive function that tries to reenter during first stake
    receive() external payable {
        ttb.stake(3600 ether);
    }
}