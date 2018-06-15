pragma solidity ^0.4.23;


import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../node_modules/openzeppelin-solidity/contracts/payment/PullPayment.sol";
import "../node_modules/openzeppelin-solidity/contracts/ReentrancyGuard.sol";
import "../node_modules/openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "../node_modules/openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";


contract ERC20TokenExchange is PullPayment, ReentrancyGuard {

    using SafeMath for uint256;

    event SellOrderPut(address _erc20TokenAddress, address _seller, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);
    event SellOrderFilled(address _erc20TokenAddress, address _seller, address _buyer, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);

    event BuyOrderPut(address _erc20TokenAddress, address _buyer, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);
    event BuyOrderFilled(address _erc20TokenAddress, address _buyer, address _seller, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);

    struct Order {

        uint256 tokenPerLot;
        uint256 pricePerLot;
        uint256 numOfLot;

    }

    mapping(address => mapping(address => Order)) public sellOrders;
    mapping(address => mapping(address => Order)) public buyOrders;

    function deposit() public payable nonReentrant {
        require(msg.value != 0);
        asyncSend(msg.sender, msg.value);
    }

    function putSellOrder(address _erc20TokenAddress, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToSell) public nonReentrant {

        require(_erc20TokenAddress != address(0));
        require(_tokenPerLot != 0);
        require(_pricePerLot != 0);
        require(_lotToSell != 0);

        Order storage order = sellOrders[_erc20TokenAddress][msg.sender];
        order.tokenPerLot = _tokenPerLot;
        order.pricePerLot = _pricePerLot;
        order.numOfLot = _lotToSell;

        ERC20 erc20 = ERC20(_erc20TokenAddress);
        require(hasSufficientTokenInternal(erc20, msg.sender, _lotToSell.mul(_tokenPerLot)));

        emit SellOrderPut(_erc20TokenAddress, msg.sender, _tokenPerLot, _pricePerLot, _lotToSell);
    }

    function fillSellOrder(address _erc20TokenAddress, address _seller, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToBuy) public payable nonReentrant {

        require(_erc20TokenAddress != address(0));
        require(_seller != address(0));
        require(_lotToBuy != 0);

        Order storage order = sellOrders[_erc20TokenAddress][_seller];
        require(order.tokenPerLot == _tokenPerLot);
        require(order.pricePerLot == _pricePerLot);
        uint256 numOfLot = order.numOfLot;
        require(numOfLot >= _lotToBuy);

        uint256 payment = _pricePerLot.mul(_lotToBuy);
        require(payment != 0);

        if (payment < msg.value) {
            asyncSend(_seller, payment);
            asyncSend(msg.sender, msg.value.sub(payment));
        } else if (payment == msg.value) {
            asyncSend(_seller, payment);
        } else {
            if (msg.value != 0) {
                asyncSend(msg.sender, msg.value);
            }
            asyncTransfer(msg.sender, _seller, payment);
        }

        order.numOfLot = numOfLot.sub(_lotToBuy);

        uint256 amoutToBuy = _lotToBuy.mul(_tokenPerLot);

        ERC20 erc20 = ERC20(_erc20TokenAddress);
        safeSafeTransferFrom(erc20, _seller, msg.sender, amoutToBuy);
        
        emit SellOrderFilled(_erc20TokenAddress, _seller, msg.sender, _tokenPerLot, _pricePerLot, _lotToBuy);
    }

    function putBuyOrder(address _erc20TokenAddress, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToBuy) public payable nonReentrant {

        require(_erc20TokenAddress != address(0));
        require(_tokenPerLot != 0);
        require(_pricePerLot != 0);
        require(_lotToBuy != 0);

        if (msg.value != 0) {
            asyncSend(msg.sender, msg.value);
        }
        require(hasSufficientPaymentInternal(msg.sender, _pricePerLot.mul(_lotToBuy)));            

        Order storage order = buyOrders[_erc20TokenAddress][msg.sender];
        order.tokenPerLot = _tokenPerLot;
        order.pricePerLot = _pricePerLot;
        order.numOfLot = _lotToBuy;

        emit BuyOrderPut(_erc20TokenAddress, msg.sender, _tokenPerLot, _pricePerLot, _lotToBuy);
    }

    function fillBuyOrder(address _erc20TokenAddress, address _buyer, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToSell) public nonReentrant {
        require(_erc20TokenAddress != address(0));
        require(_buyer != address(0));
        require(_tokenPerLot != 0);
        require(_pricePerLot != 0);
        require(_lotToSell != 0);

        Order storage order = buyOrders[_erc20TokenAddress][_buyer];
        uint256 numOfLot = order.numOfLot;

        require(numOfLot >= _lotToSell);
        require(order.tokenPerLot == _tokenPerLot);
        require(order.pricePerLot == _pricePerLot);

        uint256 payment = _pricePerLot.mul(_lotToSell);

        asyncTransfer(_buyer, msg.sender, payment);
        order.numOfLot = numOfLot.sub(_lotToSell);

        ERC20 erc20 = ERC20(_erc20TokenAddress);

        uint256 amoutToSell = _lotToSell.mul(_tokenPerLot);
        safeSafeTransferFrom(erc20, msg.sender, _buyer, amoutToSell);

        emit SellOrderFilled(_erc20TokenAddress, _buyer, msg.sender, _tokenPerLot, _pricePerLot, _lotToSell);
    }

    function safeSafeTransferFrom(ERC20 _erc20, address _from, address _to, uint256 _amount) internal {
        uint256 previousBalance = _erc20.balanceOf(_to);        
        SafeERC20.safeTransferFrom(_erc20, _from, _to, _amount);
        require(previousBalance.add(_amount) == _erc20.balanceOf(_to));
    }

    function isValidSellOrder(address _erc20TokenAddress, address _seller) public view returns(bool) {
        ERC20 erc20 = ERC20(_erc20TokenAddress);
        Order storage order = sellOrders[_erc20TokenAddress][_seller];
        return hasSufficientTokenInternal(erc20, _seller, order.tokenPerLot.mul(order.numOfLot));
    }

    function isValidBuyOrder(address _erc20TokenAddress, address _buyer) public view returns(bool) {
        Order storage order = buyOrders[_erc20TokenAddress][_buyer];
        return hasSufficientPaymentInternal(_buyer, order.pricePerLot.mul(order.numOfLot));
    }

    function getSellOrderInfo(address _erc20TokenAddress, address _seller) public view returns(uint256, uint256, uint256) {
        Order storage order = sellOrders[_erc20TokenAddress][_seller];
        return (order.tokenPerLot, order.pricePerLot, order.numOfLot);
    }

    function getBuyOrderInfo(address _erc20TokenAddress, address _buyer) public view returns(uint256, uint256, uint256) {
        Order storage order = buyOrders[_erc20TokenAddress][_buyer];
        return (order.tokenPerLot, order.pricePerLot, order.numOfLot);
    }

    function asyncTransfer(address _from, address _to, uint256 amount) internal {
        uint256 balance = payments[_from];
        require(balance >= amount);
        payments[_from] = balance.sub(amount);
        payments[_to] = payments[_to].add(amount);
    }

    function hasSufficientPaymentInternal(address _payee, uint256 _amount) internal view returns(bool) {
        return payments[_payee] >= _amount;
    }

    function hasSufficientTokenInternal(ERC20 erc20, address _seller, uint256 _amountToSell) internal view returns(bool) {
        return erc20.allowance(_seller, address(this)) >= _amountToSell;
    }

}