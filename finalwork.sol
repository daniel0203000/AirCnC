// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DecentralizedCarRental {
    uint256 public nextCarId;

    //車子結構
    struct Car {
        uint256 carId;
        bool isscooter;
        address payable owner;
        string locate;     
        bytes model;
        bytes plate;           
        uint256 pricePerHour;   
        uint32 fdcanstart;     
        uint32 ldcanstart;     
        uint8 status;          
        bytes imageURL;        
        bytes phone;           
    }
    //租約細節結構
    struct RentalInfo {
        uint256 carId;
        address payable renter;
        uint64 startTimestamp;
        uint64 endTimestamp;
        uint256 ftotalCost;
        bool isActive;
        bool renterConfirmed;
        bool ownerConfirmed;
        bool extraFeePaid;
    }

    mapping(uint256 => Car) public cars;
    mapping(uint256 => RentalInfo) public rentals;
    mapping(address => uint256[]) public ownerToCarIds;
    mapping(address => uint256[]) public renterToCarIds;
    mapping(address => uint256) public ownerBalances;

    event CarListed(uint256 carId, address indexed owner, bytes model, bytes plate, uint256 pricePerHour);
    event Caroffline(uint256 carId);
    event CarRented(uint256 carId, address indexed renter, uint64 rentstart, uint64 rentend, uint256 totalCost);
    event RentalStart(uint256 carId, address indexed renter);
    event RentalEnded(uint256 carId, address indexed renter);
    event ExtraCharged(uint256 carId, address renter, uint64 extraHours, uint256 extraCost);
    event RentalCancelled(uint256 carId, address indexed renter, uint256 refundedAmount);

    /*車主功能*/
    //上傳車輛
    function addCar(
        bool _isscooter,
        string memory _locate,
        bytes memory _model,
        bytes memory _plate,
        uint256 _pricePerHour,
        uint32 _fdcanstart,
        uint32 _ldcanstart,
        bytes memory _imageURL,
        bytes memory _phone
    ) external {
        require(_pricePerHour > 0, "Price must be greater than zero");

        cars[nextCarId] = Car({
            carId: nextCarId,
            isscooter: _isscooter,
            owner: payable(msg.sender),
            locate: _locate,
            model: _model,
            plate: _plate,
            pricePerHour: _pricePerHour,
            fdcanstart: _fdcanstart,
            ldcanstart: _ldcanstart,
            status: 1,
            imageURL: _imageURL,
            phone: _phone
        });

        ownerToCarIds[msg.sender].push(nextCarId);
        emit CarListed(nextCarId, msg.sender, _model, _plate, _pricePerHour);

        nextCarId++;
    }
    //下架車輛
    function setCarAvailability(uint256 _carId) external {
        Car storage car = cars[_carId];
        require(car.status == 1, "Can't change your car status");
        require(car.owner == msg.sender, "Not the car owner");
        car.status = 5;
        emit Caroffline(_carId);
    }

    /*租客功能*/
    //租車功能
    function rentCar(uint256 _carId, uint256 totalCost, uint64 rentstart, uint64 rentend) external payable {
        Car storage car = cars[_carId];
        require(car.status == 1, "Car is not available");
        require(car.owner != msg.sender, "Owner cannot rent own car");
        require(totalCost >= car.pricePerHour, "Must rent for at least 1 hour");
        require(msg.value >= totalCost, "Insufficient ETH sent");

        uint256 overpaid = msg.value - totalCost;
        if (overpaid > 0) {
            payable(msg.sender).transfer(overpaid);
        }

        ownerBalances[car.owner] += totalCost;

        rentals[_carId] = RentalInfo({
            carId: _carId,
            renter: payable(msg.sender),
            startTimestamp: rentstart,
            endTimestamp: rentend,
            ftotalCost: totalCost,
            isActive: false,
            renterConfirmed: false,
            ownerConfirmed: false,
            extraFeePaid: false
        });

        renterToCarIds[msg.sender].push(_carId);
        car.status = 2;
        emit CarRented(_carId, msg.sender, rentstart, rentend, totalCost);
    }

    //取消租車
    function cancelRental(uint256 _carId) external {
        RentalInfo storage rent = rentals[_carId];
        Car storage car = cars[_carId];

        require(rent.renter == msg.sender, "Only renter can cancel");
        require(!rent.isActive, "Rental already started");
        require(rent.ftotalCost > 0, "Rental already cancelled or does not exist");
        require(ownerBalances[car.owner] >= rent.ftotalCost, "Owner has insufficient balance for refund");

        uint256 refundAmount = rent.ftotalCost;
        ownerBalances[car.owner] -= refundAmount;
        rent.ftotalCost = 0;
        payable(msg.sender).transfer(refundAmount);

        rent.startTimestamp = 0;
        rent.endTimestamp = 0;
        rent.renter = payable(address(0));

        car.status = 1;
        emit RentalCancelled(_carId, msg.sender, refundAmount);
    }

    /*雙方功能*/
    //確認租車
    function startRental(uint256 _carId) external {
        RentalInfo storage rent = rentals[_carId];
        Car storage car = cars[_carId];

        require(
            msg.sender == car.owner || msg.sender == rent.renter,
            "Only renter or owner can confirm start"
        );
        require(car.status == 2, "Car has not been rented");

        if (msg.sender == rent.renter) {
            rent.renterConfirmed = true;
        } else if (msg.sender == car.owner) {
            rent.ownerConfirmed = true;
        }

        if (rent.renterConfirmed && rent.ownerConfirmed) {
            rent.isActive = true;
            car.status = 3;
            emit RentalStart(_carId, rent.renter);
        }
    }

    //結束租車並確認超時費用
    function endRental(uint256 _carId, uint64 overtimeHours) external payable {
        RentalInfo storage rent = rentals[_carId];
        Car storage car = cars[_carId];
        require(car.status == 3, "Car is not currently rented");
        require(msg.sender == car.owner || msg.sender == rent.renter, "Only renter or owner can confirm return");
        require(rent.isActive, "No active rental");

        if (overtimeHours == 0) {
            rent.extraFeePaid = true;
            if (msg.value > 0) {
                payable(msg.sender).transfer(msg.value);
            }
        }

        if (!rent.extraFeePaid) {
            require(msg.sender == rent.renter, "Renter needs to pay extra fee");
        }

        if (overtimeHours > 0 && !rent.extraFeePaid) {
            uint256 extraCost = uint256(overtimeHours) * car.pricePerHour;
            require(msg.value >= extraCost, "Insufficient ETH for overtime");
            uint256 refund = msg.value - extraCost;
            if (refund > 0) {
                payable(msg.sender).transfer(refund);
            }
            ownerBalances[car.owner] += extraCost;

            rent.ftotalCost += extraCost;
            rent.extraFeePaid = true;
            emit ExtraCharged(_carId, rent.renter, overtimeHours, extraCost);
        }

        if (msg.sender == rent.renter) {
            rent.renterConfirmed = false;
        } else if (msg.sender == car.owner) {
            rent.ownerConfirmed = false;
        }

        if (!rent.renterConfirmed && !rent.ownerConfirmed && rent.extraFeePaid) {
            rent.isActive = false;
            car.status = 4;

            uint256 totalPayment = rent.ftotalCost;
            require(address(this).balance >= totalPayment, "Contract has insufficient balance");
            ownerBalances[car.owner] -= totalPayment;
            car.owner.transfer(totalPayment);

            emit RentalEnded(_carId, rent.renter);
        }
    }

    /*查詢功能*/
    ///取得車主合約內餘額(未領出)
    function getOwnerBalance(address _owner) external view returns (uint256) {
        return ownerBalances[_owner];
    }
    ///取得車主所有上傳的車
    function getMyCars() external view returns (Car[] memory) {
        uint256[] memory myCarIds = ownerToCarIds[msg.sender];
        Car[] memory myCars = new Car[](myCarIds.length);
        for (uint256 i = 0; i < myCarIds.length; i++) {
            myCars[i] = cars[myCarIds[i]];
        }
        return myCars;
    }
    ///取得車子資訊
    function getCar(uint256 _carId) external view returns (Car memory) {
        return cars[_carId];
    }
    ///取得我的所有租約資訊
    function getMyRentals() external view returns (RentalInfo[] memory) {
        uint256[] memory carIds = renterToCarIds[msg.sender];
        RentalInfo[] memory myRentals = new RentalInfo[](carIds.length);
        for (uint256 i = 0; i < carIds.length; i++) {
            myRentals[i] = rentals[carIds[i]];
        }
        return myRentals;
    }
    ///取得可出租車子
    function getAvailableCars() external view returns (uint256[] memory) {
        uint256 availableCount = 0;
        for (uint256 i = 0; i < nextCarId; i++) {
            if (cars[i].status == 1) {
                availableCount++;
            }
        }
        uint256[] memory result = new uint256[](availableCount);
        uint256 index = 0;
        for (uint256 i = 0; i < nextCarId; i++) {
            if (cars[i].status == 1) {
                result[index] = i;
                index++;
            }
        }
        return result;
    }
}