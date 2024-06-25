//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test , console} from "../../lib/forge-std/src/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test{

    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;
    uint256 entranceFee ; 
    uint256 interval ; 
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle,helperConfig) = deployer.run();
        (
        entranceFee , 
        interval , 
        vrfCoordinator, 
        gasLane, 
        subscriptionId, 
        callbackGasLimit,
        link,
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER,STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view{
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    //////////////////////////////////
    ////      Enter Raffle       /////
    //////////////////////////////////

    function testRaffleRevertWhenYouDontPayEnough() public {
        // Arrange

        vm.prank(PLAYER);

        // Act
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();

        // Assert
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value:entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnteredRaffleEvent() public {
        vm.prank(PLAYER);
        vm.expectEmit(true,false,false,false,address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value:entranceFee}();
    }
    function testCantEnterRaffleWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value:entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value:entranceFee}();
    }




    //////////////////////////////////
    ////      CheckUp Keep       /////
    //////////////////////////////////

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");


        //Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value:entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        //ACT
        (bool checkUpkeep,) = raffle.checkUpkeep("");

        //assert
        assert(checkUpkeep == false);
    }

    //////////////////////////////////
    ////     PerformUpkeep       /////
    //////////////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value:entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number +1);

        // ACT and Assert
        raffle.performUpkeep("");
    }

    function testPerformupkeepRevertsIfCheckUpkeepIsFalse() public {
        vm.expectRevert();
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed {
        vm.prank(PLAYER);
        raffle.enterRaffle{value:entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }
    function testPerformUpkeepUpdatesRafflStateAndEmitsRequestId() public raffleEnteredAndTimePassed{
        //Arrange
            // Handled though modifier

        //Act
        vm.recordLogs();
        raffle.performUpkeep("");    // This emits requestID
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 requestId = entries[0].topics[1];
        Raffle.RaffleState rState = raffle.getRaffleState();

        //Assert
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }



    //////////////////////////////////
    ////    FulfillRandomWords   /////
    //////////////////////////////////


    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEnteredAndTimePassed {
        // Arrange
        vm.expectRevert();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId,address(raffle));

        //Act



        //Assert
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendMoney() public raffleEnteredAndTimePassed {

        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for(uint256 i =startingIndex; i < startingIndex + additionalEntrants ; i++) {
            address player = address(uint160(i));
            hoax(player,STARTING_USER_BALANCE);
            raffle.enterRaffle{value:entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants);

        vm.recordLogs();
        raffle.performUpkeep("");    // This emits requestID
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 requestId;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("RandomnessRequested(bytes32)")) {
                requestId = abi.decode(entries[i].data, (bytes32));
                break;
            }
        }
        console.log(uint256(requestId));

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId) ,
            address(raffle)
        );

        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getNumberOfPlayers() != 0);
        assert(raffle.getRecentWinner().balance == STARTING_USER_BALANCE + prize);

    }
}