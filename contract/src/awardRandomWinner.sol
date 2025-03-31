// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

contract AutomatedLottery is VRFConsumerBaseV2, AutomationCompatibleInterface {
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 public entranceFee = 0.01 ether;
    address payable[] private players;
    address private currentWinner;
    uint256 private lastTimeStamp;
    uint256 private immutable interval = 300;

    event LotteryEnter(address indexed player);
    event RequestedLotteryWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed winner, uint256 amount);

    constructor(
        address vrfCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        lastTimeStamp = block.timestamp;
        i_callbackGasLimit = callbackGasLimit;
    }

    function playInLottery() public payable {
        if (msg.value < entranceFee) {
            revert("Not enough ETH to enter lottery");
        }

        players.push(payable(msg.sender));
        emit LotteryEnter(msg.sender);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timePassed = ((block.timestamp - lastTimeStamp) > interval);
        bool hasPlayers = (players.length > 1);
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert("Upkeep not needed");
        }
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedLotteryWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        uint256 winnerIndex = randomWords[0] % players.length;
        address payable recentWinner = players[winnerIndex];
        currentWinner = recentWinner;
        players = new address payable[](0);
        lastTimeStamp = block.timestamp;
        uint256 prizeAmount = (address(this).balance * 95) / 100;
        (bool success, ) = recentWinner.call{value: prizeAmount}("");
        if (!success) {
            revert("Transfer failed");
        }
        emit WinnerPicked(recentWinner, prizeAmount);
    }

    function getEntranceFee() public view returns (uint256) {
        return entranceFee;
    }

    function setEntranceFee(uint256 _fee) public {
        entranceFee = _fee;
    }

    function getRecentWinner() public view returns (address) {
        return currentWinner;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return lastTimeStamp;
    }
}
