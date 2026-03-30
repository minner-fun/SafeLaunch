// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "@solady/tokens/ERC721.sol";
import {Initializable} from "@solady/utils/Initializable.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {LibClone} from "@solady/utils/LibClone.sol";
import {LibString} from "@solady/utils/LibString.sol";

import {IMLaunch} from "src/interfaces/IMLaunch.sol";
import {TokenSupply} from "src/contracts/libraries/TokenSupply.sol";

import {PositionManager} from "src/contracts/PositionManager.sol";
import {IMemecoin} from "src/interfaces/IMemecoin.sol";


contract MLaunch is ERC721, IMLaunch, Initializable, Ownable {
    uint256 public constant MAX_SCHEDULE_DURATION = 30 days;
    uint256 public constant MAX_FAIR_LAUNCH_TOKENS = TokenSupply.INITIAL_SUPPLY;

    uint256 public s_nextTokenId = 1;
    PositionManager public s_positionManager;

    string internal s_name = 'Mlaunch';
    string internal s_symbol = 'MLAUNCH';
    string public s_baseURI;

    address public s_memecoinImplementation;
    address public s_memecoinTreasuryImplementation;
    

    struct TokenInfo {
        address memecoin;
        address payable memecoinTreasury;
    }

    mapping(address _memecoin => uint256 _tokenId) public s_tokenId;
    mapping(uint256 _tokenId => TokenInfo _tokenInfo) public s_tokenInfo;

    error MLaunch_InvalidMlaunchSchedule();
    error MLaunch_InvalidInitialSupply(uint256 _initialSupply);
    error MLaunch_CallerIsNotPositionManager();
    error MLaunch_TokenDoseNotExist();


    modifier onlyPositionManager(){
        if(msg.sender != address(s_positionManager)){
            revert MLaunch_CallerIsNotPositionManager();
        }
        _;
    }

    constructor(address _memecoinImplementation, string memory _baseURI) {
        s_memecoinImplementation = _memecoinImplementation;
        s_baseURI = _baseURI;
        _initializeOwner(msg.sender);
    }

    function initialize(PositionManager _positionManager, address _memecoinTreasuryImplementation)
        external
        onlyOwner
        initializer
    {
        s_positionManager = _positionManager;
        s_memecoinTreasuryImplementation = _memecoinTreasuryImplementation;
    }

    function mlaunch(PositionManager.MLaunchParams calldata _params)
        external
        override
        onlyPositionManager
        returns (address memecoin_, address payable memecoinTreasury_, uint256 tokenId_)
    {
        if (_params.mlaunchAt > block.timestamp + MAX_SCHEDULE_DURATION) {
            revert MLaunch_InvalidMlaunchSchedule();
        }

        if (_params.initialTokenFairLaunch > MAX_FAIR_LAUNCH_TOKENS) {
            revert MLaunch_InvalidInitialSupply(_params.initialTokenFairLaunch);
        }

        tokenId_ = s_nextTokenId;
        unchecked {
            s_nextTokenId++;
        }

        _mint(_params.creator, tokenId_);

        memecoin_ = LibClone.cloneDeterministic(s_memecoinImplementation, bytes32(tokenId_));
        s_tokenId[memecoin_] = tokenId_;
        IMemecoin _memecoin = IMemecoin(memecoin_);
        _memecoin.initialize(_params.name, _params.symbol, _params.tokenUri);

        memecoinTreasury_ = payable(LibClone.cloneDeterministic(s_memecoinTreasuryImplementation, bytes32(tokenId_)));

        s_tokenInfo[tokenId_] = TokenInfo(memecoin_, memecoinTreasury_);

        _memecoin.mint(address(s_positionManager), TokenSupply.INITIAL_SUPPLY);
    }

    function name() public view override returns (string memory){
        return s_name;
    }

    function symbol() public view override returns (string memory){
        return s_symbol;
    }

    function tokenURI(uint _tokenId) public view override returns (string memory){
        if (_tokenId == 0 || _tokenId >= s_nextTokenId){
            revert MLaunch_TokenDoseNotExist();
        }
        if (bytes(s_baseURI).length == 0){
            return IMemecoin(s_tokenInfo[_tokenId].memecoin).tokenURI();
        }
        return LibString.concat(s_baseURI, LibString.toString(_tokenId));
    }

}
