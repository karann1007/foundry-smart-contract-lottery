// SPDX-License-Identifier: MIT


pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle contractr
 * @author Karan Singh
 * @notice The contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2{

    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();

    enum RaffleState {
        OPEN,    // 0
        CALCULATING    // 1
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentwinner;
    RaffleState s_raffleState;
    address s_link;
    uint256 deployerKey;

    /* EVENTS */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entranceFee , 
        uint256 interval , 
        address vrfCoordinator, 
        bytes32 gasLane, 
        uint64 subscriptionId, 
        uint32 callbackGasLimit,
        address link
        ) VRFConsumerBaseV2(vrfCoordinator){
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_link = link;
    }

    function enterRaffle() external payable{
        // require(msg.value >= i_entranceFee,"Not enough ETH sent!")
        if(msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if(s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    function checkUpkeep( bytes memory ) public view returns (bool upKeepNeeded, bytes memory) {
        bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool isRaffleOpen = s_raffleState == RaffleState.OPEN ;
        bool hasBalance = address(this).balance > 0 ;
        bool hasPlayers = s_players.length > 0;
        upKeepNeeded = timeHasPassed && isRaffleOpen && hasBalance && hasPlayers;
        return (upKeepNeeded,"0x0");
    }


    // - Get a random number
    // - Use random number to pick a player
    // - Make this all automatic
    function performUpkeep(bytes calldata) external {
        (bool upKeepNeeded , ) = checkUpkeep('');
        if(!upKeepNeeded) {
            revert();
        }
        s_raffleState = RaffleState.CALCULATING;
        i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        // CHECKS



        // EFFECTS
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentwinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);


        // INTERACT( with other contracts)
        (bool success,) = s_recentwinner.call{value:address(this).balance}("");
        if(!success) {
            revert Raffle__TransferFailed();
        }
    }

    // GETTER FUNCTIONS

    function getEntranceFee() external view returns(uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) public view returns(address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() view public returns(address){
        return s_recentwinner;
    }
    
    function getNumberOfPlayers() view public returns(uint256) {
        return s_players.length;
    }
}