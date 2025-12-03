-- Pet Hotel & Grooming

DROP DATABASE IF EXISTS PetHotelDB;
CREATE DATABASE PetHotelDB;
USE PetHotelDB;

-- Tables

-- 1. Employee
	CREATE TABLE Employee (
		employee_id INT AUTO_INCREMENT PRIMARY KEY,
		first_name  VARCHAR(50) NOT NULL,
		last_name   VARCHAR(50) NOT NULL,
		email       VARCHAR(100) NOT NULL UNIQUE,
		phone       VARCHAR(20),
		hire_date   DATE NOT NULL,
		role        ENUM('Admin','Manager','Staff') NOT NULL,
		is_manager  TINYINT(1) DEFAULT 0,
		CONSTRAINT chk_role_manager CHECK (
			(role = 'Manager' AND is_manager = 1) OR (role <> 'Manager')
		)
	);

-- 2. Pet_Owner (Customers)
	CREATE TABLE Pet_Owner (
		owner_id   INT AUTO_INCREMENT PRIMARY KEY,
		first_name VARCHAR(50) NOT NULL,
		last_name  VARCHAR(50) NOT NULL,
		email      VARCHAR(100) NOT NULL UNIQUE,
		phone      VARCHAR(20),
		address    VARCHAR(200)
	);

-- 3. Service
	CREATE TABLE Service (
		service_id   INT AUTO_INCREMENT PRIMARY KEY,
		description  VARCHAR(256) NOT NULL,
		price        DECIMAL(10,2) NOT NULL CHECK (price >= 0),
		service_type ENUM('Boarding','Grooming','Training','Daycare') NOT NULL
	);

-- 4. Inventory
	CREATE TABLE Inventory (
		item_id   INT AUTO_INCREMENT PRIMARY KEY,
		item_name VARCHAR(100) NOT NULL UNIQUE,
		category  ENUM('Grooming','Food','Cleaning','Medical') NOT NULL,
		quantity  INT NOT NULL CHECK (quantity >= 0)
	);

-- 5. Pet
	CREATE TABLE Pet (
		pet_id     INT AUTO_INCREMENT PRIMARY KEY,
		owner_id   INT NOT NULL,
		pet_name   VARCHAR(50) NOT NULL,
		species    VARCHAR(50) NOT NULL,
		breed      VARCHAR(50),
		birth_date DATE,
		FOREIGN KEY (owner_id) REFERENCES Pet_Owner(owner_id)
			ON DELETE CASCADE
	);

-- 6. Reservation
	CREATE TABLE Reservation (
		reservation_id  INT AUTO_INCREMENT PRIMARY KEY,
		pet_id          INT NOT NULL,
		employee_id     INT NOT NULL,
		approved_by     INT,
		start_timeslot  DATETIME NOT NULL,
		end_timeslot    DATETIME NOT NULL,
		status          ENUM('Pending','Approved','Checked-in','Checked-out','Cancelled')
						DEFAULT 'Pending',
		FOREIGN KEY (pet_id) REFERENCES Pet(pet_id),
		FOREIGN KEY (employee_id) REFERENCES Employee(employee_id),
		FOREIGN KEY (approved_by) REFERENCES Employee(employee_id),
		CONSTRAINT chk_res_times CHECK (start_timeslot < end_timeslot)
	);

-- 7. Reservation_Service
	CREATE TABLE Reservation_Service (
		rs_id          INT AUTO_INCREMENT PRIMARY KEY,
		reservation_id INT NOT NULL,
		service_id     INT NOT NULL,
		quantity       INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
		FOREIGN KEY (reservation_id) REFERENCES Reservation(reservation_id)
			ON DELETE CASCADE,
		FOREIGN KEY (service_id) REFERENCES Service(service_id),
		UNIQUE (reservation_id, service_id)
	);

-- 8. Payment
	CREATE TABLE Payment (
		payment_id     INT AUTO_INCREMENT PRIMARY KEY,
		reservation_id INT NOT NULL,
		amount         DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
		payment_date   DATE NOT NULL,
		payment_method ENUM('Cash','Card','Online') NOT NULL,
		FOREIGN KEY (reservation_id) REFERENCES Reservation(reservation_id)
	);

-- 9. Shift
	CREATE TABLE Shift (
		shift_id   INT AUTO_INCREMENT PRIMARY KEY,
		shift_date DATE NOT NULL,
		start_time TIME NOT NULL,
		end_time   TIME NOT NULL,
		manager_id INT NOT NULL,
		FOREIGN KEY (manager_id) REFERENCES Employee(employee_id),
		CONSTRAINT chk_shift_time CHECK (start_time < end_time)
	);

-- 10. Shift_Assignment
	CREATE TABLE Shift_Assignment (
		assignment_id INT AUTO_INCREMENT PRIMARY KEY,
		shift_id      INT NOT NULL,
		employee_id   INT NOT NULL,
		FOREIGN KEY (shift_id) REFERENCES Shift(shift_id)
			ON DELETE CASCADE,
		FOREIGN KEY (employee_id) REFERENCES Employee(employee_id),
		UNIQUE (shift_id, employee_id)
	);

-- 11. Inventory_Usage
	CREATE TABLE Inventory_Usage (
		usage_id    INT AUTO_INCREMENT PRIMARY KEY,
		service_id  INT NOT NULL,
		item_id     INT NOT NULL,
		amount_used INT NOT NULL CHECK (amount_used > 0),
		FOREIGN KEY (service_id) REFERENCES Service(service_id),
		FOREIGN KEY (item_id) REFERENCES Inventory(item_id)
	);

-- 12. User_Login
	CREATE TABLE User_Login (
		user_id       INT AUTO_INCREMENT PRIMARY KEY,
		username      VARCHAR(50) NOT NULL UNIQUE,
		password_hash VARCHAR(256) NOT NULL,

		user_type     ENUM('Employee','Customer') NOT NULL,

		employee_id   INT NULL,
		owner_id      INT NULL,

		CONSTRAINT chk_user_type CHECK (
			(user_type = 'Employee' AND employee_id IS NOT NULL AND owner_id IS NULL)
			OR
			(user_type = 'Customer' AND owner_id IS NOT NULL AND employee_id IS NULL)
		),

		FOREIGN KEY (employee_id) REFERENCES Employee(employee_id)
			ON DELETE CASCADE,

		FOREIGN KEY (owner_id) REFERENCES Pet_Owner(owner_id)
			ON DELETE CASCADE
	);

-- 13. Owner_Stats
	CREATE TABLE Owner_Stats (
		owner_id     INT PRIMARY KEY,
		total_spent  DECIMAL(10,2) NOT NULL DEFAULT 0,
		last_updated DATE NOT NULL,
		FOREIGN KEY (owner_id) REFERENCES Pet_Owner(owner_id)
			ON DELETE CASCADE
	);

-- Index

	CREATE INDEX idx_pet_owner ON Pet(owner_id);
	CREATE INDEX idx_res_pet ON Reservation(pet_id);
	CREATE INDEX idx_res_status ON Reservation(status);
	CREATE INDEX idx_shift_date ON Shift(shift_date);
	CREATE INDEX idx_service_type ON Service(service_type);
	CREATE INDEX idx_inventory_category ON Inventory(category);

-- Views

	-- Total spending per owner
	CREATE VIEW vw_owner_spending AS
	SELECT 
		po.owner_id,
		CONCAT(po.first_name, ' ', po.last_name) AS owner_name,
		IFNULL(SUM(p.amount),0) AS total_spent
	FROM Pet_Owner po
	LEFT JOIN Pet pt ON pt.owner_id = po.owner_id
	LEFT JOIN Reservation r ON r.pet_id = pt.pet_id
	LEFT JOIN Payment p ON p.reservation_id = r.reservation_id
	GROUP BY po.owner_id;

	-- Upcoming reservations
	CREATE VIEW vw_upcoming_reservations AS
	SELECT 
		r.reservation_id,
		pt.pet_name,
		r.start_timeslot,
		r.status
	FROM Reservation r
	JOIN Pet pt ON r.pet_id = pt.pet_id
	WHERE r.start_timeslot > NOW();

-- Function

	DELIMITER $$

	CREATE FUNCTION pet_age(pet_birth DATE)
	RETURNS INT
	DETERMINISTIC
	BEGIN
		RETURN TIMESTAMPDIFF(YEAR, pet_birth, CURDATE());
	END $$

	DELIMITER ;

-- Trigger

	DELIMITER $$

	CREATE TRIGGER trg_inventory_decrement
	AFTER INSERT ON Inventory_Usage
	FOR EACH ROW
	BEGIN
		UPDATE Inventory
		SET quantity = quantity - NEW.amount_used
		WHERE item_id = NEW.item_id;
	END $$

	DELIMITER ;

-- Stored procedure

	DELIMITER $$

	CREATE PROCEDURE checkout_reservation(IN p_reservation INT)
	BEGIN
		DECLARE total_cost DECIMAL(10,2);

		SELECT SUM(s.price * rs.quantity)
		INTO total_cost
		FROM Reservation_Service rs
		JOIN Service s ON s.service_id = rs.service_id
		WHERE rs.reservation_id = p_reservation;

		IF total_cost IS NULL THEN 
			SET total_cost = 0;
		END IF;

		INSERT INTO Payment (reservation_id, amount, payment_date, payment_method)
		VALUES (p_reservation, total_cost, CURDATE(), 'Cash');

		UPDATE Reservation
		SET status = 'Checked-out'
		WHERE reservation_id = p_reservation;
	END $$

	DELIMITER ;

-- Procedure (cursor based)

	DELIMITER $$

	CREATE PROCEDURE refresh_owner_stats()
	BEGIN
		DECLARE done INT DEFAULT 0;
		DECLARE v_owner INT;
		DECLARE v_total DECIMAL(10,2);

		DECLARE cur CURSOR FOR
			SELECT po.owner_id,
				   IFNULL(SUM(pay.amount),0)
			FROM Pet_Owner po
			LEFT JOIN Pet pt ON po.owner_id = pt.owner_id
			LEFT JOIN Reservation r ON r.pet_id = pt.pet_id
			LEFT JOIN Payment pay ON pay.reservation_id = r.reservation_id
			GROUP BY po.owner_id;

		DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

		OPEN cur;

		read_loop: LOOP
			FETCH cur INTO v_owner, v_total;
			IF done = 1 THEN LEAVE read_loop; END IF;

			INSERT INTO Owner_Stats (owner_id, total_spent, last_updated)
			VALUES (v_owner, v_total, CURDATE())
			ON DUPLICATE KEY UPDATE
				total_spent = VALUES(total_spent),
				last_updated = VALUES(last_updated);
		END LOOP;

		CLOSE cur;
	END $$

	DELIMITER ;

-- Made up data for the database

	INSERT INTO Employee (first_name,last_name,email,phone,hire_date,role,is_manager) VALUES
	('Sarah','Cole','s.cole@example.com','4145550101','2022-01-10','Manager',1),
	('James','Ray','j.ray@example.com','4145550102','2023-03-11','Staff',0),
	('Maria','Lopez','m.lopez@example.com','4145550103','2024-05-20','Admin',0);

	INSERT INTO Pet_Owner (first_name,last_name,email,phone,address) VALUES
	('Emily','Stone','emstone@gmail.com','4140001111','Milwaukee, WI'),
	('David','Park','dpark@gmail.com','4140002222','Oak Creek, WI');

	INSERT INTO Pet (owner_id,pet_name,species,breed,birth_date) VALUES
	(1,'Buddy','Dog','Golden Retriever','2020-08-10'),
	(1,'Luna','Dog','Poodle','2021-04-15'),
	(2,'Milo','Cat','Siamese','2019-01-05');

	INSERT INTO Service (description,price,service_type) VALUES
	('Full Grooming Package',60,'Grooming'),
	('Overnight Boarding',45,'Boarding'),
	('Daycare - Half Day',25,'Daycare');

	INSERT INTO Inventory (item_name,category,quantity) VALUES
	('Shampoo Bottle','Grooming',50),
	('Dog Food Bag','Food',100),
	('Cat Food Bag','Food',80),
	('Cleaning Spray','Cleaning',40);

	INSERT INTO Shift (shift_date,start_time,end_time,manager_id) VALUES
	('2025-01-10','08:00:00','16:00:00',1),
	('2025-01-10','16:00:00','23:00:00',1);

	INSERT INTO Shift_Assignment (shift_id,employee_id) VALUES
	(1,1),(1,2),(2,2),(2,3);

	INSERT INTO Reservation (pet_id,employee_id,approved_by,start_timeslot,end_timeslot,status) VALUES
	(1,2,1,'2025-01-11 09:00:00','2025-01-11 11:00:00','Approved'),
	(2,2,1,'2025-01-12 10:00:00','2025-01-13 10:00:00','Approved'),
	(3,2,1,'2025-01-14 08:00:00','2025-01-14 18:00:00','Pending');

	INSERT INTO Reservation_Service (reservation_id,service_id,quantity) VALUES
	(1,1,1),
	(2,2,1),
	(3,3,1);

	INSERT INTO Inventory_Usage (service_id,item_id,amount_used) VALUES
	(1,1,2),
	(2,2,1);

	INSERT INTO Payment (reservation_id,amount,payment_date,payment_method) VALUES
	(1,60,'2025-01-11','Card');

	INSERT INTO User_Login (username,password_hash,user_type,employee_id)
	VALUES ('sarah.manager','hashedpw1','Employee',1);

	INSERT INTO User_Login (username,password_hash,user_type,owner_id)
	VALUES ('emily.customer','hashedpw2','Customer',1);

CALL refresh_owner_stats();