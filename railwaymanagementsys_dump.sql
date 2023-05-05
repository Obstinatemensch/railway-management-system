--
-- PostgreSQL database dump
--

-- Dumped from database version 15.1
-- Dumped by pg_dump version 15.1 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cancel_seat(integer, integer, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancel_seat(IN pnr_no_ integer, IN usr_id integer, IN pass_ids text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    rec_stBtw record;
    rec_pass record;
    bkng_no INTEGER;
    totalFare INTEGER;
    trxn_id_ INTEGER;
    pass_ids_arr INTEGER[];
    src_ VARCHAR(4);
    dst_ VARCHAR(4);
    coach_no_ VARCHAR(4);
    seat_no_ INTEGER;
    tno_ INTEGER;
    DOJ TIMESTAMP;
BEGIN
    -- Convert the comma-separated string to an array
    pass_ids_arr := string_to_array(pass_ids, ',');

    IF ((SELECT count(*) FROM pass_tkt where pnr_no=pnr_no_) = 0) THEN
        RAISE NOTICE 'No such booking found with specified pnr number';
        RETURN;
    END IF;
    -- fetching booking number, trxn_id, tno_
    SELECT booking_id INTO bkng_no FROM pass_tkt where pnr_no=pnr_no_;
    -- RAISE NOTICE 'bkng_no (%)', bkng_no;

    SELECT MAX(txn_id) INTO trxn_id_ FROM Booking where booking_id=bkng_no;        --select highest txn id; multiple part-cancellations allowed
    -- RAISE NOTICE 'MAX(txn_id) (%)', trxn_id_;
    
    SELECT train_no INTO tno_ FROM pass_tkt where pnr_no=pnr_no_;
    -- RAISE NOTICE 'tno_ (%)', tno_;

    SELECT src_date INTO DOJ FROM pass_tkt where pnr_no=pnr_no_;
    -- RAISE NOTICE 'DOJ (%)', DOJ;

    totalFare := 0;       -- base fare not to be refunded

    -- for each passenger who wish to be cancelled
    FOR rec_pass IN SELECT unnest(pass_ids_arr) AS passr_id LOOP
        -- getting src dst for that pass; general case
        SELECT src INTO src_ FROM pass_tkt where pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;
        SELECT dest INTO dst_ FROM pass_tkt where pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;
        SELECT coach_no INTO coach_no_ FROM pass_tkt where pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;
        SELECT seat_no INTO seat_no_ FROM pass_tkt where pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;

        UPDATE pass_tkt SET "isConfirmed"='CAN' WHERE pnr_no=pnr_no_ AND pass_id=rec_pass.passr_id;
        totalFare := totalFare + (SELECT count(*) FROM station_between(tno_,src_,src_))*25 + 0;

        -- mark the seat unbooked for the entire duration (except dest) in Reservation table
        FOR rec_stBtw IN SELECT * FROM station_between(tno_,src_,dst_) WHERE station_id != dst_ LOOP
            UPDATE Reservation
            SET is_booked='N' WHERE src_date=DOJ AND train_no=tno_ AND coach_no=coach_no_ AND seat_no=seat_no_ AND station=rec_stBtw.station_id;
        END LOOP;
        RAISE NOTICE 'cancelled pass_id = %', (rec_pass.passr_id);
    END LOOP;

    totalFare := totalFare * -1;

    -- add to booking table
    INSERT INTO Booking ("booking_id","fare","txn_id","user_id","booking_date")
    VALUES
    (bkng_no,totalFare,(trxn_id_*2)+1,usr_id,NOW());
    RAISE NOTICE 'refund ₹%', (-1*totalFare);

END;
$$;


ALTER PROCEDURE public.cancel_seat(IN pnr_no_ integer, IN usr_id integer, IN pass_ids text) OWNER TO postgres;

--
-- Name: cancel_ticket(integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.cancel_ticket(IN p_pnr_no integer, IN p_pass_id integer)
    LANGUAGE plpgsql
    AS $$
declare
    v_train_no INTEGER;
    v_src VARCHAR(4);
    v_dest VARCHAR(4);
    v_coach_no VARCHAR(5);
    v_seat_no INTEGER;
    v_curr_stn VARCHAR(4);
    v_next_stn VARCHAR(4);
BEGIN
    -- Get the train number, source station, and destination station for the given PNR number
    SELECT train_no, src, dest INTO v_train_no, v_src, v_dest
    FROM pass_tkt
    WHERE pnr_no = p_pnr_no AND pass_id = p_pass_id;

    -- Get the coach number and seat number for the given PNR number
    SELECT coach_no, seat_no INTO v_coach_no, v_seat_no
    FROM Reservation
    WHERE train_no = v_train_no AND is_booked = 'Y' AND seat_no IN (
        SELECT seat_no
        FROM pass_tkt
        WHERE pnr_no = p_pnr_no AND pass_id = p_pass_id
    );

    -- Update the Reservation table to mark the seat as unbooked
    UPDATE Reservation
    SET is_booked = 'N'
    WHERE train_no = v_train_no AND coach_no = v_coach_no AND seat_no = v_seat_no;

    -- Update the Seat_Status table to mark the seat as available
    UPDATE Seat_Status
    SET occupancy_status = 'AVAILABLE', current_pass_id = NULL, current_pnr_no = NULL
    WHERE train_no = v_train_no AND coach_no = v_coach_no AND seat_no = v_seat_no;

    -- Check if there is a next station after the source station
    SELECT stn_id INTO v_curr_stn
    FROM Schedule
    WHERE train_no = v_train_no AND stn_id = v_src;

    SELECT stn_id INTO v_next_stn
    FROM Schedule
    WHERE train_no = v_train_no AND Dayofjny = (
        SELECT Dayofjny
        FROM Schedule
        WHERE train_no = v_train_no AND stn_id = v_src
    ) AND arr_time > (
        SELECT arr_time
        FROM Schedule
        WHERE train_no = v_train_no AND stn_id = v_src
    )
    ORDER BY arr_time
    FETCH FIRST 1 ROW ONLY;

    -- If there is a next station, update the Seat_Status table to mark the seat between the current and next stations as available
    IF v_next_stn IS NOT NULL THEN
        UPDATE Seat_Status
        SET occupancy_status = 'AVAILABLE'
        WHERE train_no = v_train_no AND coach_no = v_coach_no AND seat_no IN (
            SELECT seat_no
            FROM Reservation
            WHERE train_no = v_train_no AND is_booked = 'N' AND coach_no = v_coach_no AND seat_no IN (
                SELECT seat_no
                FROM Schedule
                WHERE train_no = v_train_no AND stn_id = v_next_stn
            )
        );
    END IF;
END $$;


ALTER PROCEDURE public.cancel_ticket(IN p_pnr_no integer, IN p_pass_id integer) OWNER TO postgres;

--
-- Name: num_available(integer, character varying, character varying, timestamp without time zone, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.num_available(tno integer, src character varying, dst character varying, doj timestamp without time zone, c_typ character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
cnt INTEGER;
rec_res record;
rec_stBtw record;
rec record;
flag BOOLEAN;
BEGIN
    cnt := 0;
    FOR rec_res in SELECT DISTINCT coach_no AS coach_no_,seat_no AS seat_no_ FROM Reservation WHERE src_date=DOJ AND train_no=tno AND coach_type=c_typ LOOP
        flag := false;
        IF (SELECT count(*) FROM station_between(tno,src,dst) WHERE station_id != dst)=0 THEN
            flag := true;
        END IF;
        FOR rec_stBtw in SELECT * FROM station_between(tno,src,dst) WHERE station_id != dst LOOP
            IF (SELECT is_booked FROM Reservation WHERE src_date=DOJ AND train_no=tno AND coach_no=rec_res.coach_no_ AND seat_no=rec_res.seat_no_ AND station=rec_stBtw.station_id)='Y' THEN
                flag := true;
            END IF;
        END LOOP;
        IF flag=false THEN
            cnt := cnt+1;
        END IF;
    END LOOP;
    return cnt;
END;
$$;


ALTER FUNCTION public.num_available(tno integer, src character varying, dst character varying, doj timestamp without time zone, c_typ character varying) OWNER TO postgres;

--
-- Name: reserve_seat(integer, character varying, character varying, timestamp without time zone, character varying, integer, integer, text); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.reserve_seat(IN tno integer, IN src character varying, IN dst character varying, IN doj timestamp without time zone, IN c_typ character varying, IN usr_id integer, IN trxn_id integer, IN pass_ids text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    rec_res record;
    rec_stBtw record;
    rec_pass record;
    flag BOOLEAN;
    pnr_no_ INTEGER;
    bkng_no INTEGER;
    totalFare INTEGER;
    pass_ids_arr INTEGER[];
BEGIN
    -- Convert the comma-separated string to an array
    pass_ids_arr := string_to_array(pass_ids, ',');

    IF (SELECT num_available(tno,src,dst,doj,c_typ)) < array_length(pass_ids_arr, 1) THEN
        RAISE NOTICE 'Not enough seats available';
        RETURN;
    END IF;

    -- generating pnr number and booking number
    SELECT count(*) INTO pnr_no_ FROM pass_tkt;
    pnr_no_ := pnr_no_ + 56734512;
    SELECT count(*) INTO bkng_no FROM Booking;
    bkng_no := bkng_no + 73772234;

    -- for each passenger
    FOR rec_pass IN SELECT unnest(pass_ids_arr) AS passr_id LOOP
        FOR rec_res IN SELECT DISTINCT coach_no AS coach_no_,seat_no AS seat_no_ FROM Reservation WHERE src_date=DOJ AND train_no=tno AND coach_type=c_typ LOOP
            flag := false;
            FOR rec_stBtw IN SELECT * FROM station_between(tno,src,dst) WHERE station_id != dst LOOP
                IF (SELECT is_booked FROM Reservation WHERE src_date=DOJ AND train_no=tno AND coach_no=rec_res.coach_no_ AND seat_no=rec_res.seat_no_ AND station=rec_stBtw.station_id)='Y' THEN
                    flag := true;
                END IF;
            END LOOP;

            -- when a suitable seat is found
            IF flag=false THEN
                -- INITIATE BOOKING PROCESS for the passenger 

                -- mark the seat booked for the entire duration (except dest) in Reservation table
                FOR rec_stBtw IN SELECT * FROM station_between(tno,src,dst) WHERE station_id != dst LOOP
                    UPDATE Reservation
                    SET is_booked='Y' WHERE src_date=DOJ AND train_no=tno AND coach_no=rec_res.coach_no_ AND seat_no=rec_res.seat_no_ AND station=rec_stBtw.station_id;
                END LOOP;

                -- add to pass_tkt table
                INSERT INTO pass_tkt ("pnr_no","src_date","pass_id","booking_id","train_no","coach_no","seat_no","food_order_id","src","dest","isConfirmed")
                VALUES
                (pnr_no_,doj,rec_pass.passr_id,bkng_no,tno,rec_res.coach_no_,rec_res.seat_no_,NULL,src,dst,'CNF');


                EXIT;
                -- BOOKING DONE
            END IF;
        END LOOP;
    END LOOP;

    totalFare := 35 + array_length(pass_ids_arr, 1)*(SELECT count(*) FROM station_between(tno,src,dst))*30 + 0;

    -- add to booking table
    INSERT INTO Booking ("booking_id","fare","txn_id","user_id","booking_date")
    VALUES
    (bkng_no,totalFare,trxn_id,usr_id,NOW());

END;
$$;


ALTER PROCEDURE public.reserve_seat(IN tno integer, IN src character varying, IN dst character varying, IN doj timestamp without time zone, IN c_typ character varying, IN usr_id integer, IN trxn_id integer, IN pass_ids text) OWNER TO postgres;

--
-- Name: station_between(integer, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.station_between(p_train_no integer, p_start_stn character varying, p_end_stn character varying) RETURNS TABLE(station_id character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT stn_id
    FROM Schedule
    WHERE train_no = p_train_no 
    AND (
            ( -- single day travel
                (
                    (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_start_stn
                    )
                    =
                    (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_end_stn
                    )
                ) AND (
                    "Dayofjny" = (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_start_stn
                    )
                ) AND (
                    dep_time >= (
                        SELECT dep_time
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_start_stn
                    )
                ) AND (
                    arr_time <= (
                        SELECT arr_time
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_end_stn
                    )
                )
)
            OR
            ( -- multi day travel
                (
                    (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_start_stn
                    )
                    <
                    (
                        SELECT "Dayofjny"
                        FROM Schedule
                        WHERE train_no = p_train_no AND stn_id = p_end_stn
                    )
                ) AND 
                (
                    ( -- first doj
                        (
                            "Dayofjny" = (
                                SELECT "Dayofjny"
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_start_stn
                            )
                        ) AND (
                            dep_time >= (
                                SELECT dep_time
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_start_stn
                            )
                        )
                    )
OR
                    ( -- last doj
                        (
                            "Dayofjny" = (
                                SELECT "Dayofjny"
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_end_stn
                            )
                        ) AND (
                            arr_time <= (
                                SELECT arr_time
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_end_stn
                            )
                        )
                    )
                    OR
                    ( -- intermediate doj
                        (
                            "Dayofjny" > (
                                SELECT "Dayofjny"
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_start_stn
                            )
                        ) AND (
                            "Dayofjny" < (
                                SELECT "Dayofjny"
                                FROM Schedule
                                WHERE train_no = p_train_no AND stn_id = p_end_stn
                            )
                        )
                    )
                )
            )
        )
    ORDER BY "Dayofjny",dep_time;
END;
$$;


ALTER FUNCTION public.station_between(p_train_no integer, p_start_stn character varying, p_end_stn character varying) OWNER TO postgres;

--
-- Name: trainsbtwstns(character varying, character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trainsbtwstns(src_id character varying, dst_id character varying, day integer) RETURNS TABLE(train_no integer, src_stn_id character varying, dest_stn_id character varying, days_of_wk integer, src_arr_time time without time zone, src_dep_time time without time zone, dest_arr_time time without time zone, dest_dep_time time without time zone, daynum integer)
    LANGUAGE plpgsql
    AS $$
-- declare 
-- variable declaration
begin
RETURN QUERY
SELECT s1.train_no,s1.stn_id,s2.stn_id,s1.days_of_wk,s1.arr_time,s1.dep_time,s2.arr_time,s2.dep_time,s2."Dayofjny"-s1."Dayofjny" FROM Schedule as s1 cross join Schedule as s2 where (s1.days_of_wk&(1<<day))>0 and s1.train_no=s2.train_no and s1.stn_id=src_id and s2.stn_id=dst_id and (s1."Dayofjny"<s2."Dayofjny" or (s1."Dayofjny"=s2."Dayofjny" and s1.dep_time<s2.arr_time));
end; $$;


ALTER FUNCTION public.trainsbtwstns(src_id character varying, dst_id character varying, day integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: booking; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.booking (
    booking_id integer NOT NULL,
    fare integer NOT NULL,
    txn_id integer NOT NULL,
    user_id integer,
    booking_date timestamp without time zone
);


ALTER TABLE public.booking OWNER TO postgres;

--
-- Name: food; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food (
    food_order_id integer NOT NULL,
    item character varying(50) NOT NULL,
    booking_id integer,
    price numeric,
    del_time timestamp without time zone
);


ALTER TABLE public.food OWNER TO postgres;

--
-- Name: food_ordered; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_ordered (
    food_order_id integer NOT NULL,
    item character varying(50) NOT NULL,
    pass_id integer NOT NULL,
    pnr_no numeric NOT NULL
);


ALTER TABLE public.food_ordered OWNER TO postgres;

--
-- Name: new_user; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.new_user (
    user_id integer NOT NULL,
    name character varying(30),
    email character varying(50),
    "phNo" numeric,
    aadhar numeric,
    address character varying(50),
    dob timestamp without time zone,
    password character varying(20)
);


ALTER TABLE public.new_user OWNER TO postgres;

--
-- Name: parcel_tkt; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.parcel_tkt (
    parcel_no integer NOT NULL,
    booking_id integer,
    train_no integer,
    src character varying(5),
    dest character varying(5),
    weight integer,
    "isConfirmed" character varying(1)
);


ALTER TABLE public.parcel_tkt OWNER TO postgres;

--
-- Name: pass_tkt; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pass_tkt (
    pnr_no integer NOT NULL,
    src_date timestamp without time zone,
    pass_id integer NOT NULL,
    booking_id integer NOT NULL,
    train_no integer NOT NULL,
    coach_no character varying(5),
    seat_no integer,
    food_order_id integer,
    src character varying(4) NOT NULL,
    dest character varying(4) NOT NULL,
    "isConfirmed" character varying(3) NOT NULL,
    CONSTRAINT "pass_tkt_isConfirmed_check" CHECK ((("isConfirmed")::text = ANY ((ARRAY['CNF'::character varying, 'WL'::character varying, 'RAC'::character varying, 'CAN'::character varying])::text[])))
);


ALTER TABLE public.pass_tkt OWNER TO postgres;

--
-- Name: passenger; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.passenger (
    pass_id integer NOT NULL,
    name character varying(20),
    age integer,
    gender character varying(5),
    nationality character varying(20),
    concsn_type character varying(20),
    user_id integer,
    CONSTRAINT passenger_age_check CHECK ((age >= 0)),
    CONSTRAINT passenger_concsn_type_check CHECK (((concsn_type)::text = ANY ((ARRAY['senior_ctzn'::character varying, 'armed_forces'::character varying, 'student'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT passenger_gender_check CHECK (((gender)::text = ANY ((ARRAY['M'::character varying, 'F'::character varying, 'Other'::character varying])::text[])))
);


ALTER TABLE public.passenger OWNER TO postgres;

--
-- Name: reservation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservation (
    src_date timestamp without time zone NOT NULL,
    train_no integer NOT NULL,
    coach_no character varying(5) NOT NULL,
    coach_type character varying(5),
    seat_no integer NOT NULL,
    station character varying(4) NOT NULL,
    is_booked character varying(1) NOT NULL,
    seat_type character varying(5),
    CONSTRAINT reservation_is_booked_check CHECK (((is_booked)::text = ANY ((ARRAY['Y'::character varying, 'N'::character varying])::text[]))),
    CONSTRAINT reservation_seat_type_check CHECK (((seat_type)::text = ANY ((ARRAY['W'::character varying, 'M'::character varying, 'A'::character varying, 'SU'::character varying, 'SL'::character varying, 'UB'::character varying, 'LB'::character varying, 'MB'::character varying])::text[])))
);


ALTER TABLE public.reservation OWNER TO postgres;

--
-- Name: schedule; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schedule (
    train_no integer NOT NULL,
    stn_id character varying(4) NOT NULL,
    days_of_wk integer NOT NULL,
    arr_time time without time zone,
    dep_time time without time zone,
    "Dayofjny" integer NOT NULL
);


ALTER TABLE public.schedule OWNER TO postgres;

--
-- Name: seat_status; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.seat_status (
    train_no integer NOT NULL,
    coach_no character varying(5) NOT NULL,
    seat_no integer NOT NULL,
    occupancy_status character varying(10) NOT NULL,
    current_pass_id integer,
    current_pnr_no integer,
    CONSTRAINT seat_status_occupancy_status_check CHECK (((occupancy_status)::text = ANY ((ARRAY['AVAILABLE'::character varying, 'BOOKED'::character varying, 'CONFIRMED'::character varying])::text[])))
);


ALTER TABLE public.seat_status OWNER TO postgres;

--
-- Name: station; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.station (
    stn_id character varying(4) NOT NULL,
    station_name character varying(20),
    address character varying(60)
);


ALTER TABLE public.station OWNER TO postgres;

--
-- Name: stns; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stns (
    stn_id character varying(4)
);


ALTER TABLE public.stns OWNER TO postgres;

--
-- Name: temptable; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.temptable (
    passr_id integer
);


ALTER TABLE public.temptable OWNER TO postgres;

--
-- Name: train; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.train (
    train_no integer NOT NULL,
    train_name character varying(20) NOT NULL,
    src character varying(4) NOT NULL,
    dest character varying(4) NOT NULL
);


ALTER TABLE public.train OWNER TO postgres;

--
-- Data for Name: booking; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.booking (booking_id, fare, txn_id, user_id, booking_date) FROM stdin;
73772234	155	229607	66637	2023-05-04 16:11:16.490156
73772234	-50	459215	66637	2023-05-04 16:45:02.829158
73772236	155	901326	5533	2023-05-04 16:55:56.105927
73772237	155	41115	5533	2023-05-04 17:01:15.080148
73772238	155	483223	5533	2023-05-04 17:03:01.519614
73772237	-50	82231	5533	2023-05-04 17:09:56.521972
73772240	305	856757	66637	2023-05-05 21:58:45.389154
73772240	-50	1713515	66637	2023-05-05 22:01:32.234759
73772240	-25	3427031	66637	2023-05-05 22:01:56.61874
73772243	305	236877	66637	2023-05-05 22:03:11.551365
73772243	-75	473755	66637	2023-05-05 22:05:57.785122
73772238	-50	966447	5533	2023-05-05 22:06:58.304088
73772236	-50	1802653	5533	2023-05-05 22:07:15.98756
73772247	305	918835	66637	2023-05-05 22:07:56.941192
73772247	-75	1837671	66637	2023-05-05 22:11:52.460167
73772249	215	783271	66637	2023-05-05 22:12:15.144917
73772249	-50	1566543	66637	2023-05-05 22:25:05.215665
73772251	305	202005	66637	2023-05-05 22:26:22.87838
73772251	-75	404011	66637	2023-05-05 22:27:08.333943
73772253	305	517507	5533	2023-05-05 22:27:37.417997
73772253	-75	1035015	5533	2023-05-05 22:28:08.65267
73772255	305	816659	66637	2023-05-05 22:29:31.728093
73772255	-75	1633319	66637	2023-05-05 22:35:48.440516
73772257	305	306712	66637	2023-05-05 22:36:13.377945
73772258	155	82945	66637	2023-05-05 22:37:40.444232
73772258	-50	165891	66637	2023-05-05 22:38:19.576145
73772257	-75	613425	66637	2023-05-05 22:38:27.525804
73772261	215	146653	66637	2023-05-05 22:40:09.007668
73772262	395	855182	66637	2023-05-05 22:41:31.746435
73772263	215	922351	66637	2023-05-05 22:44:17.007644
73772264	215	199505	66637	2023-05-05 22:46:21.103932
73772264	0	399011	66637	2023-05-05 22:49:07.700493
73772263	0	1844703	66637	2023-05-05 22:49:14.98269
73772261	-50	293307	66637	2023-05-05 22:49:22.500814
73772262	-100	1710365	66637	2023-05-05 22:49:33.549876
73772269	305	478424	66637	2023-05-05 22:49:57.50881
73772270	515	692422	66637	2023-05-05 23:02:09.442523
73772271	95	529458	66637	2023-05-05 23:20:04.91107
73772269	-75	956849	66637	2023-05-05 23:20:46.839535
73772271	-25	1058917	66637	2023-05-05 23:20:53.972407
73772270	0	1384845	66637	2023-05-05 23:21:02.989134
73772275	125	993238	66637	2023-05-05 23:21:54.491857
73772275	-25	1986477	66637	2023-05-05 23:22:54.790615
73772277	125	74410	66637	2023-05-05 23:23:07.477962
73772277	-25	148821	66637	2023-05-05 23:24:36.242469
73772279	125	267557	66637	2023-05-05 23:24:58.440247
73772280	125	887897	66637	2023-05-05 23:25:51.532201
73772281	305	210397	5533	2023-05-05 23:32:09.685805
73772281	-50	420795	5533	2023-05-05 23:33:12.79672
73772280	-25	1775795	66637	2023-05-05 23:35:55.867748
73772284	215	680034	66637	2023-05-05 23:36:35.455421
73772285	155	124902	66637	2023-05-05 23:39:49.093277
73772286	155	485041	66637	2023-05-05 23:40:56.395743
73772279	-25	535115	66637	2023-05-05 23:47:23.224276
73772285	-50	249805	66637	2023-05-05 23:47:31.058785
73772286	-50	970083	66637	2023-05-05 23:47:37.091557
73772284	0	1360069	66637	2023-05-05 23:47:45.540995
73772291	395	394081	66637	2023-05-05 23:48:02.580153
73772292	215	149755	66637	2023-05-05 23:49:51.459482
73772293	125	382954	66637	2023-05-05 23:51:36.627313
73772294	125	781339	66637	2023-05-05 23:55:15.382648
\.


--
-- Data for Name: food; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food (food_order_id, item, booking_id, price, del_time) FROM stdin;
\.


--
-- Data for Name: food_ordered; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_ordered (food_order_id, item, pass_id, pnr_no) FROM stdin;
\.


--
-- Data for Name: new_user; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.new_user (user_id, name, email, "phNo", aadhar, address, dob, password) FROM stdin;
1234	NAM	ww@ww.com	9699	9696969	addr qwwr  aw, aew, r	2023-05-02 00:00:00	pass123
5533	NAM4	s24ww@w4w.com	9699	69696969	addr qwwr  aw, a2ew, r	2003-05-02 00:00:00	0000
112001051	vmsreeram	a@gmail.com	977	11223344	a h nj wajnkjfkn jwan ,sd,g,sd	2002-09-19 00:00:00	aaaa
1122	somename	12@ana.add	112222333	1222334	24, 23,r qwra,az	2002-09-19 00:00:00	1122pass
998877	abcd	efgh@wmmm.wsw	444444	222222	44m.we.,3r32,rq3rw,	2020-09-19 00:00:00	9999
\.


--
-- Data for Name: parcel_tkt; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.parcel_tkt (parcel_no, booking_id, train_no, src, dest, weight, "isConfirmed") FROM stdin;
\.


--
-- Data for Name: pass_tkt; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pass_tkt (pnr_no, src_date, pass_id, booking_id, train_no, coach_no, seat_no, food_order_id, src, dest, "isConfirmed") FROM stdin;
56734512	2023-05-06 00:00:00	8	73772234	16606	C1	1	\N	ALLP	ERS	CAN
56734512	2023-05-06 00:00:00	9	73772234	16606	C1	2	\N	ALLP	ERS	CAN
56734516	2023-05-23 00:00:00	10	73772237	12076	C1	1	\N	ERS	CLT	CAN
56734516	2023-05-23 00:00:00	11	73772237	12076	C1	2	\N	ERS	CLT	CAN
56734520	2023-05-06 00:00:00	9	73772240	16606	C1	3	\N	ERS	CLT	CAN
56734520	2023-05-06 00:00:00	124	73772240	16606	C1	1	\N	ERS	CLT	CAN
56734520	2023-05-06 00:00:00	8	73772240	16606	C1	2	\N	ERS	CLT	CAN
56734523	2023-05-06 00:00:00	8	73772243	16606	C1	2	\N	ERS	CLT	CAN
56734523	2023-05-06 00:00:00	9	73772243	16606	C1	3	\N	ERS	CLT	CAN
56734523	2023-05-06 00:00:00	124	73772243	16606	C1	1	\N	ERS	CLT	CAN
56734518	2023-05-06 00:00:00	10	73772238	16606	C1	3	\N	TVC	ALLP	CAN
56734518	2023-05-06 00:00:00	1223	73772238	16606	C1	1	\N	TVC	ALLP	CAN
56734537	2023-05-06 00:00:00	8	73772255	16606	C1	2	\N	ERS	CLT	CAN
56734537	2023-05-06 00:00:00	9	73772255	16606	C1	3	\N	ERS	CLT	CAN
56734537	2023-05-06 00:00:00	124	73772255	16606	C1	1	\N	ERS	CLT	CAN
56734543	2023-05-06 00:00:00	8	73772258	16606	C2	4	\N	ALLP	ERS	CAN
56734543	2023-05-06 00:00:00	9	73772258	16606	C2	3	\N	ALLP	ERS	CAN
56734540	2023-05-06 00:00:00	8	73772257	16606	C1	2	\N	ERS	CLT	CAN
56734514	2023-05-06 00:00:00	10	73772236	16606	C1	1	\N	ALLP	ERS	CAN
56734514	2023-05-06 00:00:00	11	73772236	16606	C1	2	\N	ALLP	ERS	CAN
56734540	2023-05-06 00:00:00	9	73772257	16606	C1	3	\N	ERS	CLT	CAN
56734540	2023-05-06 00:00:00	124	73772257	16606	C1	1	\N	ERS	CLT	CAN
56734553	2023-05-23 00:00:00	8	73772264	12076	C1	1	\N	TVC	ERS	CAN
56734553	2023-05-23 00:00:00	9	73772264	12076	C1	2	\N	TVC	ERS	CAN
56734551	2023-05-23 00:00:00	8	73772263	12076	C2	1	\N	TVC	ERS	CAN
56734551	2023-05-23 00:00:00	9	73772263	12076	C2	2	\N	TVC	ERS	CAN
56734545	2023-05-06 00:00:00	123	73772261	16606	C2	4	\N	TVC	ERS	CAN
56734545	2023-05-06 00:00:00	124	73772261	16606	C2	3	\N	TVC	ERS	CAN
56734547	2023-05-06 00:00:00	8	73772262	16606	C1	3	\N	ERS	CLT	CAN
56734547	2023-05-06 00:00:00	9	73772262	16606	C1	4	\N	ERS	CLT	CAN
56734547	2023-05-06 00:00:00	123	73772262	16606	C1	1	\N	ERS	CLT	CAN
56734547	2023-05-06 00:00:00	124	73772262	16606	C1	2	\N	ERS	CLT	CAN
56734555	2023-05-06 00:00:00	8	73772269	16606	C2	2	\N	ERS	CLT	CAN
56734526	2023-05-06 00:00:00	8	73772247	16606	C1	2	\N	ERS	CLT	CAN
56734526	2023-05-06 00:00:00	9	73772247	16606	C1	3	\N	ERS	CLT	CAN
56734526	2023-05-06 00:00:00	123	73772247	16606	C1	1	\N	ERS	CLT	CAN
56734529	2023-05-06 00:00:00	8	73772249	16606	C2	4	\N	ERS	CLT	CAN
56734529	2023-05-06 00:00:00	9	73772249	16606	C2	3	\N	ERS	CLT	CAN
56734531	2023-05-06 00:00:00	8	73772251	16606	C1	2	\N	TVC	ERS	CAN
56734531	2023-05-06 00:00:00	9	73772251	16606	C1	3	\N	TVC	ERS	CAN
56734531	2023-05-06 00:00:00	124	73772251	16606	C1	1	\N	TVC	ERS	CAN
56734534	2023-05-06 00:00:00	10	73772253	16606	C1	2	\N	TVC	ERS	CAN
56734534	2023-05-06 00:00:00	11	73772253	16606	C1	3	\N	TVC	ERS	CAN
56734534	2023-05-06 00:00:00	1223	73772253	16606	C1	1	\N	TVC	ERS	CAN
56734555	2023-05-06 00:00:00	123	73772269	16606	C2	4	\N	ERS	CLT	CAN
56734555	2023-05-06 00:00:00	124	73772269	16606	C2	3	\N	ERS	CLT	CAN
56734562	2023-05-06 00:00:00	12	73772271	16606	C2	4	\N	TVC	ALLP	CAN
56734558	2023-05-23 00:00:00	8	73772270	12076	C1	1	\N	TVC	CLT	CAN
56734558	2023-05-23 00:00:00	9	73772270	12076	C1	2	\N	TVC	CLT	CAN
56734558	2023-05-23 00:00:00	12	73772270	12076	C1	3	\N	TVC	CLT	CAN
56734558	2023-05-23 00:00:00	13	73772270	12076	C1	4	\N	TVC	CLT	CAN
56734563	2023-05-06 00:00:00	12	73772275	16606	C2	4	\N	ERS	CLT	CAN
56734564	2023-05-06 00:00:00	9	73772277	16606	C1	1	\N	ERS	CLT	CAN
56734567	2023-05-06 00:00:00	11	73772281	16606	C2	2	\N	ERS	CLT	CNF
56734567	2023-05-06 00:00:00	10	73772281	16606	C2	3	\N	ERS	CLT	CAN
56734567	2023-05-06 00:00:00	1223	73772281	16606	C2	4	\N	ERS	CLT	CAN
56734566	2023-05-06 00:00:00	12	73772280	16606	C1	2	\N	ERS	CLT	CAN
56734565	2023-05-06 00:00:00	13	73772279	16606	C1	1	\N	ERS	CLT	CAN
56734573	2023-05-06 00:00:00	9	73772285	16606	C1	1	\N	ALLP	ERS	CAN
56734573	2023-05-06 00:00:00	12	73772285	16606	C1	2	\N	ALLP	ERS	CAN
56734575	2023-05-06 00:00:00	9	73772286	16606	C1	2	\N	ERS	SRR	CAN
56734575	2023-05-06 00:00:00	12	73772286	16606	C1	3	\N	ERS	SRR	CAN
56734570	2023-05-23 00:00:00	9	73772284	12076	C2	1	\N	TVC	ALLP	CAN
56734570	2023-05-23 00:00:00	12	73772284	12076	C2	2	\N	TVC	ALLP	CAN
56734570	2023-05-23 00:00:00	13	73772284	12076	C2	3	\N	TVC	ALLP	CAN
56734577	2023-05-06 00:00:00	8	73772291	16606	C1	1	\N	ERS	CLT	CNF
56734577	2023-05-06 00:00:00	9	73772291	16606	C1	2	\N	ERS	CLT	CNF
56734577	2023-05-06 00:00:00	12	73772291	16606	C1	3	\N	ERS	CLT	CNF
56734577	2023-05-06 00:00:00	13	73772291	16606	C1	4	\N	ERS	CLT	CNF
56734581	2023-05-23 00:00:00	123	73772292	12076	C2	1	\N	ALLP	ERS	CNF
56734581	2023-05-23 00:00:00	12	73772292	12076	C2	2	\N	ALLP	ERS	CNF
56734581	2023-05-23 00:00:00	13	73772292	12076	C2	3	\N	ALLP	ERS	CNF
56734584	2023-05-06 00:00:00	9	73772293	16606	C2	4	\N	ERS	CLT	CNF
56734585	2023-05-06 00:00:00	12	73772294	16606	C2	3	\N	ERS	CLT	CNF
\.


--
-- Data for Name: passenger; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.passenger (pass_id, name, age, gender, nationality, concsn_type, user_id) FROM stdin;
123	pass1	22	F	Indian	student	66637
124	pass2	21	F	Indian	student	66637
1223	p1223	22	F	Indian	student	5533
8	PASS125	25	M	INDIAN	armed_forces	66637
9	PRAYAG	21	M	INDIAN	student	66637
10	Arun	20	M	Indian	student	5533
11	Somaraj	22	M	Indian	armed_forces	5533
12	Saarang	20	M	Indian	armed_forces	66637
13	Arun Sankar	20	M	Indian	other	66637
\.


--
-- Data for Name: reservation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reservation (src_date, train_no, coach_no, coach_type, seat_no, station, is_booked, seat_type) FROM stdin;
2023-05-23 00:00:00	12076	C1	CC	1	QLN	N	W
2023-05-23 00:00:00	12076	C1	CC	1	ALLP	N	W
2023-05-06 00:00:00	16606	C1	CC	3	SRR	Y	A
2023-05-23 00:00:00	12076	C1	CC	1	TVC	N	W
2023-05-23 00:00:00	12076	C1	CC	1	CLT	N	W
2023-05-23 00:00:00	12076	C1	CC	2	TVC	N	M
2023-05-06 00:00:00	16606	C1	CC	4	SRR	Y	W
2023-05-23 00:00:00	12076	C1	CC	3	QLN	N	A
2023-05-23 00:00:00	12076	C1	CC	3	ALLP	N	A
2023-05-23 00:00:00	12076	C1	CC	3	ERS	N	A
2023-05-23 00:00:00	12076	C1	CC	3	SRR	N	A
2023-05-23 00:00:00	12076	C1	CC	4	QLN	N	M
2023-05-23 00:00:00	12076	C1	CC	4	ALLP	N	M
2023-05-23 00:00:00	12076	C1	CC	4	ERS	N	M
2023-05-23 00:00:00	12076	C1	CC	4	SRR	N	M
2023-05-06 00:00:00	12431	H1	1AC	3	TVC	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	QLN	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	ERS	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	SRR	N	A
2023-05-06 00:00:00	12431	B2	3AC	1	SRR	N	W
2023-05-06 00:00:00	12431	B2	3AC	1	CLT	N	W
2023-05-06 00:00:00	12431	B2	3AC	2	CLT	N	M
2023-05-23 00:00:00	12076	C2	3AC	1	ALLP	Y	W
2023-05-23 00:00:00	12076	C2	3AC	2	ALLP	Y	M
2023-05-23 00:00:00	12076	C1	CC	2	CLT	N	M
2023-05-23 00:00:00	12076	C1	CC	3	TVC	N	A
2023-05-23 00:00:00	12076	C1	CC	3	CLT	N	A
2023-05-23 00:00:00	12076	C1	CC	4	TVC	N	M
2023-05-23 00:00:00	12076	C1	CC	4	CLT	N	M
2023-05-23 00:00:00	12076	C2	3AC	1	TVC	N	W
2023-05-23 00:00:00	12076	C2	3AC	1	ERS	N	W
2023-05-23 00:00:00	12076	C2	3AC	1	SRR	N	W
2023-05-23 00:00:00	12076	C2	3AC	1	CLT	N	W
2023-05-23 00:00:00	12076	C2	3AC	2	TVC	N	M
2023-05-23 00:00:00	12076	C2	3AC	2	ERS	N	M
2023-05-23 00:00:00	12076	C2	3AC	2	SRR	N	M
2023-05-23 00:00:00	12076	C2	3AC	2	CLT	N	M
2023-05-23 00:00:00	12076	C2	3AC	3	TVC	N	A
2023-05-23 00:00:00	12076	C2	3AC	3	ERS	N	A
2023-05-23 00:00:00	12076	C2	3AC	3	SRR	N	A
2023-05-23 00:00:00	12076	C2	3AC	3	CLT	N	A
2023-05-23 00:00:00	12076	C2	3AC	4	TVC	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	QLN	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	ALLP	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	ERS	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	SRR	N	W
2023-05-23 00:00:00	12076	C2	3AC	4	CLT	N	W
2023-05-06 00:00:00	16606	C1	CC	1	QLN	N	W
2023-05-06 00:00:00	16606	C1	CC	1	CLT	N	W
2023-05-06 00:00:00	16606	C1	CC	1	CAN	N	W
2023-05-06 00:00:00	16606	C1	CC	1	MAQ	N	W
2023-05-06 00:00:00	16606	C1	CC	2	QLN	N	M
2023-05-06 00:00:00	16606	C1	CC	2	CLT	N	M
2023-05-06 00:00:00	16606	C1	CC	2	CAN	N	M
2023-05-06 00:00:00	16606	C1	CC	2	MAQ	N	M
2023-05-06 00:00:00	16606	C1	CC	3	QLN	N	A
2023-05-06 00:00:00	16606	C1	CC	3	CLT	N	A
2023-05-06 00:00:00	16606	C1	CC	3	CAN	N	A
2023-05-06 00:00:00	16606	C1	CC	3	MAQ	N	A
2023-05-06 00:00:00	16606	C1	CC	4	QLN	N	W
2023-05-06 00:00:00	16606	C1	CC	4	CLT	N	W
2023-05-06 00:00:00	16606	C1	CC	4	CAN	N	W
2023-05-06 00:00:00	16606	C1	CC	4	MAQ	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	TVC	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	QLN	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	ALLP	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	ERS	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	SRR	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	CLT	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	CAN	N	W
2023-05-06 00:00:00	16606	C2	3AC	1	MAQ	N	W
2023-05-06 00:00:00	16606	C2	3AC	2	TVC	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	QLN	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	ALLP	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	CLT	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	CAN	N	M
2023-05-06 00:00:00	16606	C2	3AC	2	MAQ	N	M
2023-05-06 00:00:00	16606	C2	3AC	3	QLN	N	A
2023-05-06 00:00:00	16606	C2	3AC	3	CLT	N	A
2023-05-06 00:00:00	16606	C2	3AC	3	CAN	N	A
2023-05-06 00:00:00	16606	C2	3AC	3	MAQ	N	A
2023-05-06 00:00:00	16606	C2	3AC	4	QLN	N	W
2023-05-06 00:00:00	16606	C2	3AC	4	CLT	N	W
2023-05-06 00:00:00	16606	C2	3AC	4	CAN	N	W
2023-05-06 00:00:00	16606	C2	3AC	4	MAQ	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	NZM	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	CLT	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	SRR	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	ERS	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	QLN	N	W
2023-05-06 00:00:00	12432	H1	1AC	1	TVC	N	W
2023-05-06 00:00:00	12432	H1	1AC	2	NZM	N	W
2023-05-06 00:00:00	12432	H1	1AC	2	CLT	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	SRR	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	ERS	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	QLN	N	M
2023-05-06 00:00:00	12432	H1	1AC	2	TVC	N	M
2023-05-06 00:00:00	12432	H1	1AC	3	NZM	N	W
2023-05-06 00:00:00	12432	H1	1AC	3	CLT	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	SRR	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	ERS	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	QLN	N	A
2023-05-06 00:00:00	12432	H1	1AC	3	TVC	N	A
2023-05-06 00:00:00	16606	C1	CC	4	ALLP	N	W
2023-05-23 00:00:00	12076	C1	CC	1	ERS	N	W
2023-05-06 00:00:00	16606	C2	3AC	4	ALLP	N	W
2023-05-06 00:00:00	16606	C2	3AC	4	TVC	N	W
2023-05-23 00:00:00	12076	C1	CC	1	SRR	N	W
2023-05-23 00:00:00	12076	C2	3AC	1	QLN	N	W
2023-05-06 00:00:00	16606	C1	CC	3	ALLP	N	A
2023-05-06 00:00:00	16606	C2	3AC	3	ERS	Y	A
2023-05-06 00:00:00	16606	C2	3AC	3	SRR	Y	A
2023-05-23 00:00:00	12076	C2	3AC	3	ALLP	Y	A
2023-05-06 00:00:00	16606	C1	CC	1	ERS	Y	W
2023-05-06 00:00:00	16606	C2	3AC	3	TVC	N	A
2023-05-23 00:00:00	12076	C2	3AC	2	QLN	N	M
2023-05-06 00:00:00	16606	C1	CC	1	ALLP	N	W
2023-05-06 00:00:00	16606	C1	CC	2	ALLP	N	M
2023-05-06 00:00:00	16606	C1	CC	1	SRR	Y	W
2023-05-06 00:00:00	16606	C2	3AC	4	ERS	Y	W
2023-05-06 00:00:00	16606	C1	CC	2	ERS	Y	M
2023-05-23 00:00:00	12076	C1	CC	2	QLN	N	M
2023-05-06 00:00:00	16606	C2	3AC	3	ALLP	N	A
2023-05-06 00:00:00	16606	C2	3AC	4	SRR	Y	W
2023-05-23 00:00:00	12076	C1	CC	2	ALLP	N	M
2023-05-23 00:00:00	12076	C1	CC	2	ERS	N	M
2023-05-23 00:00:00	12076	C1	CC	2	SRR	N	M
2023-05-23 00:00:00	12076	C2	3AC	3	QLN	N	A
2023-05-06 00:00:00	16606	C1	CC	2	SRR	Y	M
2023-05-06 00:00:00	16606	C1	CC	3	ERS	Y	A
2023-05-06 00:00:00	16606	C2	3AC	2	ERS	Y	M
2023-05-06 00:00:00	16606	C2	3AC	2	SRR	Y	M
2023-05-06 00:00:00	16606	C1	CC	4	ERS	Y	W
2023-05-06 00:00:00	12432	H1	1AC	4	NZM	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	CLT	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	SRR	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	ERS	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	QLN	N	W
2023-05-06 00:00:00	12432	H1	1AC	4	TVC	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	NZM	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	CLT	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	SRR	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	ERS	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	QLN	N	W
2023-05-06 00:00:00	12432	A1	2AC	1	TVC	N	W
2023-05-06 00:00:00	12432	A1	2AC	2	NZM	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	CLT	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	SRR	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	ERS	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	QLN	N	M
2023-05-06 00:00:00	12432	A1	2AC	2	TVC	N	M
2023-05-06 00:00:00	12432	A1	2AC	3	NZM	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	CLT	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	SRR	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	ERS	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	QLN	N	A
2023-05-06 00:00:00	12432	A1	2AC	3	TVC	N	A
2023-05-06 00:00:00	12432	A1	2AC	4	NZM	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	CLT	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	SRR	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	ERS	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	QLN	N	W
2023-05-06 00:00:00	12432	A1	2AC	4	TVC	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	NZM	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	CLT	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	SRR	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	ERS	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	QLN	N	W
2023-05-06 00:00:00	12432	A2	2AC	1	TVC	N	W
2023-05-06 00:00:00	12432	A2	2AC	2	NZM	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	CLT	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	SRR	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	ERS	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	QLN	N	M
2023-05-06 00:00:00	12432	A2	2AC	2	TVC	N	M
2023-05-06 00:00:00	12432	A2	2AC	3	NZM	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	CLT	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	SRR	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	ERS	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	QLN	N	A
2023-05-06 00:00:00	12432	A2	2AC	3	TVC	N	A
2023-05-06 00:00:00	12432	A2	2AC	4	NZM	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	CLT	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	SRR	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	ERS	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	QLN	N	W
2023-05-06 00:00:00	12432	A2	2AC	4	TVC	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	NZM	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	CLT	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	SRR	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	ERS	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	QLN	N	W
2023-05-06 00:00:00	12432	B1	3AC	1	TVC	N	W
2023-05-06 00:00:00	12432	B1	3AC	2	NZM	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	CLT	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	SRR	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	ERS	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	QLN	N	M
2023-05-06 00:00:00	12432	B1	3AC	2	TVC	N	M
2023-05-06 00:00:00	12432	B1	3AC	3	NZM	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	CLT	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	SRR	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	ERS	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	QLN	N	A
2023-05-06 00:00:00	12432	B1	3AC	3	TVC	N	A
2023-05-06 00:00:00	12432	B1	3AC	4	NZM	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	CLT	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	SRR	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	ERS	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	QLN	N	W
2023-05-06 00:00:00	12432	B1	3AC	4	TVC	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	NZM	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	CLT	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	SRR	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	ERS	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	ALLP	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	QLN	N	W
2023-05-06 00:00:00	12432	B2	3AC	1	TVC	N	W
2023-05-06 00:00:00	12432	B2	3AC	2	NZM	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	CLT	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	SRR	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	ERS	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	ALLP	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	QLN	N	M
2023-05-06 00:00:00	12432	B2	3AC	2	TVC	N	M
2023-05-06 00:00:00	12432	B2	3AC	3	NZM	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	CLT	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	SRR	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	ERS	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	ALLP	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	QLN	N	A
2023-05-06 00:00:00	12432	B2	3AC	3	TVC	N	A
2023-05-06 00:00:00	12432	B2	3AC	4	NZM	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	CLT	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	SRR	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	ERS	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	ALLP	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	QLN	N	W
2023-05-06 00:00:00	12432	B2	3AC	4	TVC	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	TVC	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	QLN	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	ERS	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	SRR	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	CLT	N	W
2023-05-06 00:00:00	12431	H1	1AC	1	NZM	N	W
2023-05-06 00:00:00	12431	H1	1AC	2	TVC	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	QLN	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	ERS	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	SRR	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	CLT	N	M
2023-05-06 00:00:00	12431	H1	1AC	2	NZM	N	M
2023-05-06 00:00:00	12431	H1	1AC	3	CLT	N	A
2023-05-06 00:00:00	12431	H1	1AC	3	NZM	N	A
2023-05-06 00:00:00	12431	H1	1AC	4	TVC	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	QLN	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	ERS	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	SRR	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	CLT	N	W
2023-05-06 00:00:00	12431	H1	1AC	4	NZM	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	TVC	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	QLN	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	ERS	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	SRR	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	CLT	N	W
2023-05-06 00:00:00	12431	A1	2AC	1	NZM	N	W
2023-05-06 00:00:00	12431	A1	2AC	2	TVC	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	QLN	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	ERS	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	SRR	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	CLT	N	M
2023-05-06 00:00:00	12431	A1	2AC	2	NZM	N	M
2023-05-06 00:00:00	12431	A1	2AC	3	TVC	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	QLN	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	ERS	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	SRR	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	CLT	N	A
2023-05-06 00:00:00	12431	A1	2AC	3	NZM	N	A
2023-05-06 00:00:00	12431	A1	2AC	4	TVC	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	QLN	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	ERS	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	SRR	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	CLT	N	W
2023-05-06 00:00:00	12431	A1	2AC	4	NZM	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	TVC	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	QLN	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	ERS	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	SRR	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	CLT	N	W
2023-05-06 00:00:00	12431	A2	2AC	1	NZM	N	W
2023-05-06 00:00:00	12431	A2	2AC	2	TVC	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	QLN	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	ERS	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	SRR	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	CLT	N	M
2023-05-06 00:00:00	12431	A2	2AC	2	NZM	N	M
2023-05-06 00:00:00	12431	A2	2AC	3	TVC	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	QLN	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	ERS	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	SRR	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	CLT	N	A
2023-05-06 00:00:00	12431	A2	2AC	3	NZM	N	A
2023-05-06 00:00:00	12431	A2	2AC	4	TVC	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	QLN	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	ERS	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	SRR	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	CLT	N	W
2023-05-06 00:00:00	12431	A2	2AC	4	NZM	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	TVC	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	QLN	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	ERS	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	SRR	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	CLT	N	W
2023-05-06 00:00:00	12431	B1	3AC	1	NZM	N	W
2023-05-06 00:00:00	12431	B1	3AC	2	TVC	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	QLN	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	ERS	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	SRR	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	CLT	N	M
2023-05-06 00:00:00	12431	B1	3AC	2	NZM	N	M
2023-05-06 00:00:00	12431	B1	3AC	3	TVC	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	QLN	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	ERS	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	SRR	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	CLT	N	A
2023-05-06 00:00:00	12431	B1	3AC	3	NZM	N	A
2023-05-06 00:00:00	12431	B1	3AC	4	TVC	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	QLN	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	ERS	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	SRR	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	CLT	N	W
2023-05-06 00:00:00	12431	B1	3AC	4	NZM	N	W
2023-05-06 00:00:00	12431	B2	3AC	1	TVC	N	W
2023-05-06 00:00:00	12431	B2	3AC	1	NZM	N	W
2023-05-06 00:00:00	12431	B2	3AC	2	TVC	N	M
2023-05-06 00:00:00	12431	B2	3AC	2	NZM	N	M
2023-05-06 00:00:00	12431	B2	3AC	3	TVC	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	QLN	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	ALLP	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	CLT	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	NZM	N	A
2023-05-06 00:00:00	12431	B2	3AC	4	TVC	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	QLN	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	ALLP	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	ERS	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	SRR	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	CLT	N	W
2023-05-06 00:00:00	12431	B2	3AC	4	NZM	N	W
2023-05-06 00:00:00	16606	C1	CC	4	TVC	N	W
2023-05-06 00:00:00	12431	B2	3AC	3	ERS	N	A
2023-05-06 00:00:00	12431	B2	3AC	3	SRR	N	A
2023-05-06 00:00:00	12431	B2	3AC	1	QLN	N	W
2023-05-06 00:00:00	12431	B2	3AC	1	ALLP	N	W
2023-05-06 00:00:00	12431	B2	3AC	1	ERS	N	W
2023-05-06 00:00:00	12431	B2	3AC	2	QLN	N	M
2023-05-06 00:00:00	12431	B2	3AC	2	ALLP	N	M
2023-05-06 00:00:00	12431	B2	3AC	2	ERS	N	M
2023-05-06 00:00:00	12431	B2	3AC	2	SRR	N	M
2023-05-06 00:00:00	16606	C1	CC	2	TVC	N	M
2023-05-06 00:00:00	16606	C1	CC	3	TVC	N	A
2023-05-06 00:00:00	16606	C1	CC	1	TVC	N	W
\.


--
-- Data for Name: schedule; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schedule (train_no, stn_id, days_of_wk, arr_time, dep_time, "Dayofjny") FROM stdin;
16606	NCJ	127	\N	02:00:00	1
16606	TVC	127	03:30:00	03:35:00	1
16606	ALLP	127	06:15:00	06:18:00	1
16606	ERS	127	07:45:00	07:50:00	1
16606	SRR	127	10:40:00	10:45:00	1
16606	CLT	127	12:32:00	12:35:00	1
16606	CAN	127	14:12:00	14:15:00	1
16606	MAQ	127	18:00:00	\N	1
12431	TVC	26	\N	19:15:00	1
12431	QLN	26	20:11:00	20:13:00	1
12431	ALLP	26	21:33:00	21:35:00	1
12431	ERS	26	22:30:00	22:35:00	1
12431	SRR	52	00:45:00	00:50:00	2
12431	CLT	52	01:57:00	02:00:00	2
12431	NZM	104	12:30:00	\N	3
12076	TVC	127	\N	05:55:00	1
12076	QLN	127	06:55:00	06:57:00	1
12076	ALLP	127	08:13:00	08:15:00	1
12076	ERS	127	09:12:00	09:17:00	1
12076	SRR	127	11:25:00	11:28:00	1
12076	CLT	127	12:55:00	\N	1
12082	TVC	93	\N	14:45:00	1
12082	QLN	93	15:38:00	15:40:00	1
12082	KTYM	93	17:18:00	17:20:00	1
12082	ERS	93	18:30:00	18:35:00	1
12082	TCR	93	19:48:00	19:50:00	1
12082	SRR	93	20:52:00	20:55:00	1
12082	CLT	93	22:17:00	22:20:00	1
12082	CAN	110	00:20:00	\N	2
22208	TVC	17	\N	19:15:00	1
22208	QLN	17	20:11:00	20:13:00	1
22208	ALLP	17	21:33:00	21:35:00	1
22208	ERN	17	22:30:00	22:35:00	1
22208	TCR	17	23:48:00	23:50:00	1
22208	CBE	72	02:42:00	02:45:00	2
22208	SA	72	05:19:00	05:12:00	2
22208	MAS	72	10:15:00	\N	2
16605	MAQ	127	\N	07:20:00	1
16605	CAN	127	09:32:00	09:35:00	1
16605	CLT	127	11:07:00	11:10:00	1
16605	SRR	127	13:25:00	13:30:00	1
16605	ERS	127	16:15:00	16:20:00	1
16605	ALLP	127	17:48:00	17:50:00	1
16605	TVC	127	20:50:00	20:55:00	1
16605	NCJ	127	23:20:00	\N	1
12432	NZM	49	\N	06:16:00	1
12432	CLT	88	15:17:00	15:20:00	2
12432	SRR	88	16:55:00	17:00:00	2
12432	ERS	88	19:15:00	19:20:00	2
12432	ALLP	88	20:32:00	20:35:00	2
12432	QLN	88	21:53:00	21:55:00	2
12432	TVC	88	23:35:00	\N	2
\.


--
-- Data for Name: seat_status; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.seat_status (train_no, coach_no, seat_no, occupancy_status, current_pass_id, current_pnr_no) FROM stdin;
\.


--
-- Data for Name: station; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.station (stn_id, station_name, address) FROM stdin;
ERS	Ernakulam Jn	-
TVC	Trivandrum Central	-
ALLP	Alappuzha	-
CLT	Kozhikkode	-
SRR	Shoranur Jn	-
NZM	Hazrat Nizamuddin	-
QLN	Kollam Jn	-
\.


--
-- Data for Name: stns; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stns (stn_id) FROM stdin;
\.


--
-- Data for Name: temptable; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.temptable (passr_id) FROM stdin;
1234
9876
\.


--
-- Data for Name: train; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.train (train_no, train_name, src, dest) FROM stdin;
16606	ERNAD EXPRESS	NCJ	MAQ
12431	RAJDHANI EXP	TVC	NZM
12076	CLT JANSHATABDI	TVC	CLT
12082	CAN JANSHATABDI	TVC	CAN
22208	MAS SF AC EXP	TVC	MAS
16605	ERNAD EXPRESS	NCJ	MAQ
12432	TVC RAJDHANI	NZM	TVC
\.


--
-- Name: booking booking_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.booking
    ADD CONSTRAINT booking_pkey PRIMARY KEY (booking_id, txn_id);


--
-- Name: food_ordered food_ordered_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_ordered
    ADD CONSTRAINT food_ordered_pkey PRIMARY KEY (food_order_id, item, pass_id, pnr_no);


--
-- Name: food food_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food
    ADD CONSTRAINT food_pkey PRIMARY KEY (food_order_id, item);


--
-- Name: new_user new_user_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.new_user
    ADD CONSTRAINT new_user_pkey PRIMARY KEY (user_id);


--
-- Name: parcel_tkt parcel_tkt_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parcel_tkt
    ADD CONSTRAINT parcel_tkt_pkey PRIMARY KEY (parcel_no);


--
-- Name: pass_tkt pass_tkt_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pass_tkt
    ADD CONSTRAINT pass_tkt_pkey PRIMARY KEY (pnr_no, pass_id);


--
-- Name: passenger passenger_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.passenger
    ADD CONSTRAINT passenger_pkey PRIMARY KEY (pass_id);


--
-- Name: reservation reservation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservation
    ADD CONSTRAINT reservation_pkey PRIMARY KEY (src_date, train_no, coach_no, seat_no, station);


--
-- Name: schedule schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule
    ADD CONSTRAINT schedule_pkey PRIMARY KEY (train_no, stn_id, days_of_wk);


--
-- Name: seat_status seat_status_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.seat_status
    ADD CONSTRAINT seat_status_pkey PRIMARY KEY (train_no, coach_no, seat_no);


--
-- Name: station station_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.station
    ADD CONSTRAINT station_pkey PRIMARY KEY (stn_id);


--
-- Name: train train_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.train
    ADD CONSTRAINT train_pkey PRIMARY KEY (train_no);


--
-- Name: pass_tkt pass_tkt_train_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pass_tkt
    ADD CONSTRAINT pass_tkt_train_no_fkey FOREIGN KEY (train_no) REFERENCES public.train(train_no);


--
-- Name: reservation reservation_train_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservation
    ADD CONSTRAINT reservation_train_no_fkey FOREIGN KEY (train_no) REFERENCES public.train(train_no);


--
-- Name: seat_status seat_status_train_no_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.seat_status
    ADD CONSTRAINT seat_status_train_no_fkey FOREIGN KEY (train_no) REFERENCES public.train(train_no);


--
-- PostgreSQL database dump complete
--

