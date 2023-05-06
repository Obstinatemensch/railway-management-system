from datetime import time
from tkinter import *
from tkinter import ttk
from tkinter import messagebox
import sqlalchemy
from datetime import datetime
import datetime
import reportlab
from reportlab.pdfgen import canvas
import calendar
from sqlalchemy.engine import create_engine
from sqlalchemy.sql import text
import random
import os
import subprocess
import platform
from tkcalendar import DateEntry

class PostgresqlDB:
    def __init__(self,user_name,password,host,port,db_name):
        self.user_name = user_name
        self.password = password
        self.host = host
        self.port = port
        self.db_name = db_name
        self.engine = self.create_db_engine()

    def create_db_engine(self):
        try:
            db_uri = f"postgresql+psycopg2://{self.user_name}:{self.password}@{self.host}:{self.port}/{self.db_name}"
            return create_engine(db_uri)
        except Exception as err:
            raise RuntimeError(f'Failed to establish connection -- {err}') from err

    def execute_dql_commands(self,stmnt,values=None):
        try:
            with self.engine.connect() as conn:
                if values is not None:
                    result = conn.execute(text(stmnt),values)
                else:
                    result = conn.execute(text(stmnt))
            return result
        except Exception as err:
            print(f'Failed to execute dql commands -- {err}')
    
    def execute_ddl_and_dml_commands(self,stmnt,values=None):
        connection = self.engine.connect()
        trans = connection.begin()
        try:
            if values is not None:

                result = connection.execute(text(stmnt),values)
            else:
                result = connection.execute(text(stmnt))
            trans.commit()
            connection.close()
            # print('Command executed successfully.')
        except Exception as err:
            trans.rollback()
            print(f'Failed to execute ddl and dml commands -- {err}')

USER_NAME = 'postgres'
PASSWORD = 'postgres'
PORT = 5432
DATABASE_NAME = 'railwaymanagementsys'
HOST = 'localhost'

try:
    db = PostgresqlDB(user_name=USER_NAME,
                        password=PASSWORD,
                        host=HOST,port=PORT,
                        db_name=DATABASE_NAME)
    engine = db.engine
    # print('Arun')
except:
    print('Not working')
class RailwayManagementSystemGUI:
    def __init__(self, master):
        # Initialize the GUI window
        self.master = master
        self.master.title("Railway Management System")
        self.isLoggedIn = True
        # self.userId = 66637
        # self.PNR_tobecancelled = None
        self.isLoggedIn = False
        self.userId = None
        self.main_page()
    
    def main_page(self):
        
        # Create a frame for the main menu
        self.main_menu_frame = Frame(self.master)
        self.main_menu_frame.pack(pady=50)
        Label(self.main_menu_frame, text="Welcome to Railway Management System", font=("Helvetica", 20)).pack(side=TOP, pady=20)

        # Button to signup page
        btn_signup = Button(self.main_menu_frame, text="Sign up", font=("Helvetica", 16), command=self.signup_page)
        btn_signup.pack(pady=10)
        
        # Button to login page
        btn_login = Button(self.main_menu_frame, text="Login", font=("Helvetica", 16), command=self.login_page)
        btn_login.pack(pady=10)
        
        # Button to logout
        btn_logout = Button(self.main_menu_frame, text="Logout", font=("Helvetica", 16), command=self.logout)
        btn_logout.pack(pady=10)
        
        #Button to add a passenger registration page
        btn_passenger = Button(self.main_menu_frame, text="Passenger Registration", font=("Helvetica", 16), command=self.passenger_registration_page)
        btn_passenger.pack(pady=10)

        #Button to add a reservation page
        btn_reserve = Button(self.main_menu_frame, text="Reserve Seat", font=("Helvetica", 16), command=self.reserve_tickets_page)
        btn_reserve.pack(pady=10)
        
        # Button to display trains between stations
        btn_tbtwstn = Button(self.main_menu_frame, text="Trains Between Stations", font=("Helvetica", 16), command=self.trains_between_stations)
        btn_tbtwstn.pack(pady=10)

        #Button to add a cancellation page
        btn_cancel = Button(self.main_menu_frame, text="Cancel Seat", font=("Helvetica", 16), command=self.cancel_seat_page)
        btn_cancel.pack(pady=10)
        
        #Button to add a cancellation page
        btn_my = Button(self.main_menu_frame, text="My Bookings", font=("Helvetica", 16), command=self.my_bookings)
        btn_my.pack(pady=10)

        #Button to add a stnbtw page
        btn_stnbtw = Button(self.main_menu_frame, text="Find Route", font=("Helvetica", 16), command=self.station_btw)
        btn_stnbtw.pack(pady=10)

        # disabling the button reserve_page when not logged in
        if not self.isLoggedIn:
            btn_reserve.config(state="disabled")
            btn_cancel.config(state="disabled")
            btn_logout.config(state="disabled")
            btn_passenger.config(state="disabled")
            btn_my.config(state="disabled")
            
        # disabling the button for login page when logged in    
        else:
            btn_login.config(state="disabled")
            btn_signup.config(state="disabled")

    def station_btw(self):
        # Clear the main menu frame
        self.main_menu_frame.destroy()

        # Create a frame to hold the input widgets
        self.input_frame = Frame(self.master)
        self.input_frame.pack(side=LEFT, padx=10, pady=10)

        # Create labels and entry boxes for the source and destination stations
        self.srce_station_label = Label(self.input_frame, text="Start Station:")
        self.srce_station_label.grid(row=0, column=0)
        self.srce_station_entry = Entry(self.input_frame)
        self.srce_station_entry.grid(row=0, column=1)

        self.dest_station_label = Label(self.input_frame, text="End Station:")
        self.dest_station_label.grid(row=1, column=0)
        self.dest_station_entry = Entry(self.input_frame)
        self.dest_station_entry.grid(row=1, column=1)

        self.tno_label = Label(self.input_frame, text="Train No:")
        self.tno_label.grid(row=2, column=0)
        self.tno_entry = Entry(self.input_frame)
        self.tno_entry.grid(row=2, column=1)

        # Create a button to execute the query
        self.execute_button = Button(self.input_frame, text="Find Stations", command=self.findstn)
        self.execute_button.grid(row=3, column=0, columnspan=2, pady=10)

        # Create a frame to hold the output widget
        self.output_frame = Frame(self.master)
        self.output_frame.pack(side=RIGHT, padx=10, pady=10)

        # Create a label for the output widget
        self.train_list_label = Label(self.output_frame, text="Train Route:", font=("Helvetica", 20))
        self.train_list_label.pack()

        # Create a button to go back to the home page
        self.reserve_button = Button(self.input_frame, text="Go Back", command=lambda: (self.input_frame.destroy(),self.output_frame.destroy(), self.main_page()))
        self.reserve_button.grid(row=4, column=0, columnspan=2, pady=10)

        # Create a Treeview widget for the output
        self.tv = ttk.Treeview(self.output_frame, columns=(0), show='headings', height=5)
        self.tv.pack()
        self.tv.heading(0, text='Stations')

    def findstn(self):
        # Construct the query string
        query = f"SELECT station_between({self.tno_entry.get()}, '{self.srce_station_entry.get()}', '{self.dest_station_entry.get()}');"

        # Execute the query and fetch the results
        results = db.execute_dql_commands(query)
        # print(results)
        # row = results[0]

        # Clear any existing data from the Treeview widget
        for record in self.tv.get_children():
            self.tv.delete(record)

        # Insert the row into the Treeview widget
        for row in results:
            x=str(row[0])
            # print(x)
            self.tv.insert("", "end", values=(x,))

        # # Disable the input widgets and execute button
        # self.srce_station_entry.config(state="disabled")
        # self.dest_station_entry.config(state="disabled")
        # self.tno_entry.config(state="disabled")
        # self.execute_button.config(state="disabled")


    def my_bookings(self):
        query = 'select p.pnr_no, b.fare, b.txn_id, pas.name, b.booking_date from booking as b natural join pass_tkt as p join passenger as pas ON p.pass_id = pas.pass_id where pas.user_id=' +str(self.userId) + ' ORDER BY b.booking_date;'
        # print(query)
        results = db.execute_dql_commands(query)
        
        # Create a new window to display the results
        bookings_window = Toplevel(self.master)
        bookings_window.title("My Bookings")
        
        # Create a Treeview widget to display the query results
        tree = ttk.Treeview(bookings_window, columns=("pnr_no", "name", "txn_id", "fare", "booking_date"), show="headings")
        
        tree.heading("pnr_no", text="PNR No")
        tree.heading("name", text="Name")
        tree.heading("txn_id", text="Transaction ID")
        tree.heading("fare", text="Fare")
        tree.heading("booking_date", text="Booking Date")
        
        # Insert the query results into the Treeview widget
        for row in results:
            # Convert the values to the desired format before inserting them into the Treeview widget
            pnr_no = str(row[0])
            fare = str(row[1])
            txn_id = str(row[2])
            name = str(row[3])
            booking_date = row[4].strftime("%Y-%m-%d %H:%M:%S")
            tree.insert("", "end", values=(pnr_no, name, txn_id, fare, booking_date))
        
        # Pack the Treeview widget and display the window
        tree.pack(fill="both", expand=True)
        bookings_window.mainloop()

    def trains_between_stations(self):
        # Clear the main menu frame
        self.main_menu_frame.destroy()

        # Create a frame to hold the input widgets
        self.input_frame = Frame(self.master)
        self.input_frame.pack(side=LEFT, padx=10, pady=10)

        # Create labels and entry boxes for the source and destination stations
        self.source_station_label = Label(self.input_frame, text="Source Station:")
        self.source_station_label.grid(row=0, column=0)
        self.source_station_entry = Entry(self.input_frame)
        self.source_station_entry.grid(row=0, column=1)

        self.destination_station_label = Label(self.input_frame, text="Destination Station:")
        self.destination_station_label.grid(row=1, column=0)
        self.destination_station_entry = Entry(self.input_frame)
        self.destination_station_entry.grid(row=1, column=1)

        self.day_of_week_label = Label(self.input_frame, text="Date (DD-MM-YYYY):")
        self.day_of_week_label.grid(row=2, column=0)

        # Create a DateEntry widget for selecting the date of journey
        self.day_of_week_entry = DateEntry(self.input_frame, date_pattern="dd-mm-yyyy")
        self.day_of_week_entry.grid(row=2, column=1)

        # Create a button to execute the query
        self.execute_button = Button(self.input_frame, text="Find Trains", command=self.display_trains)
        self.execute_button.grid(row=3, column=0, columnspan=2, pady=10)

        # Create a frame to hold the output widget
        self.output_frame = Frame(self.master)
        self.output_frame.pack(side=RIGHT, padx=10, pady=10)

        # Create a label for the output widget
        self.train_list_label = Label(self.output_frame, text="Trains Between Stations:", font=("Helvetica", 20))
        self.train_list_label.pack()

        # Create a button to go back to the home page
        self.reserve_button = Button(self.input_frame, text="Go Back", command=lambda: (self.input_frame.destroy(),self.output_frame.destroy(), self.main_page()))
        self.reserve_button.grid(row=4, column=0, columnspan=2, pady=10)

        # Create a Treeview widget for the output
        self.train_treeview = ttk.Treeview(self.output_frame, columns=(0, 1, 2, 3, 4, 5, 6, 7, 8), show='headings', height=15)
        self.train_treeview.pack(fill='both', expand=True)

        # Configure the column headings and widths
        self.train_treeview.heading(0, text='Train Number')
        self.train_treeview.column(0, width=100)
        self.train_treeview.heading(1, text='Source Station')
        self.train_treeview.column(1, width=150)
        self.train_treeview.heading(2, text='Destination Station')
        self.train_treeview.column(2, width=150)
        self.train_treeview.heading(3, text='Days of Week')
        self.train_treeview.column(3, width=125)
        self.train_treeview.heading(4, text='Source Arrival Time')
        self.train_treeview.column(4, width=150)
        self.train_treeview.heading(5, text='Source Dept Time')
        self.train_treeview.column(5, width=150)
        self.train_treeview.heading(6, text='Dest Arrival Time')
        self.train_treeview.column(6, width=150)
        self.train_treeview.heading(7, text='Dest Dept Time')
        self.train_treeview.column(7, width=150)
        self.train_treeview.heading(8, text='Day Number')
        self.train_treeview.column(8, width=100)

        # Configure the font size
        # self.train_treeview.configure(font=('Arial', 10))

        def on_train_click(event):
            selection = self.train_treeview.selection()
            if selection:
                train_num = self.train_treeview.item(selection[0])['values'][0]
                source_station = self.source_station_entry.get()
                dest_station = self.destination_station_entry.get()

                # Create a new window for entering the coach type
                popup_window = Toplevel(self.master)
                popup_window.title("Train Details")
                popup_window.geometry("500x450")

                # Create label and dropdown menu for the coach type
                coach_label = Label(popup_window, text="Select coach type:")
                coach_label.pack()
                coach_var = StringVar(popup_window)
                coach_var.set('CC')  # Set the default value to 'CC'
                coach_menu = OptionMenu(popup_window, coach_var, 'CC', '3AC')
                coach_menu.pack()

                # Create a button to execute the query
                button = Button(popup_window, text="Check Availability", command=lambda: execute_query(train_num, source_station, dest_station, self.day_of_week_entry.get(), coach_var.get(), popup_window))
                button.pack()
                
                # coach_label = Label(popup_window, text="Route:")
                # coach_label.pack()
                # Create a button to execute the query
                self.tv1 = ttk.Treeview(popup_window, columns=(0,1), show='headings', height=10)
                self.tv1.pack(pady=100)
                self.tv1.heading(0, text='Station code')
                self.tv1.heading(1, text='Station name')
                findstn1(train_num, source_station, dest_station)
        
        def findstn1(train_num, source_station, dest_station):
            # Construct the query string
            query = f"SELECT station_between({train_num}, '{source_station}', '{dest_station}');"

            # Execute the query and fetch the results
            results = db.execute_dql_commands(query)
            # print(results)
            # row = results[0]

            # Clear any existing data from the Treeview widget
            for record in self.tv1.get_children():
                self.tv1.delete(record)

            # Insert the row into the Treeview widget
            for row in results:
                x=str(row[0])
                # print(x)
                query = f"SELECT station_name from station where stn_id=\'{x}\';"
                # print("query=",query)
                results = db.execute_dql_commands(query)
                results=list(results)
                # print("results[0]=",results[0])
                
                y=str(results[0][0])
                # print("y=",y)
                self.tv1.insert("", "end", values=(x,y,))
        
        
        def execute_query(train_num, source_station, dest_station, date, coach_type, popup_window):
            try:
                date = datetime.datetime.strptime(date, "%d-%m-%Y")
            except ValueError:
                messagebox.showerror("Error", "Invalid date format. Please use DD-MM-YYYY")
                return
            query = f"SELECT num_available({train_num}, '{source_station}', '{dest_station}', '{date}', '{coach_type}')"
            results = db.execute_dql_commands(query)
            x = list(results)
            value = x[0][0]
            messagebox.showinfo("Available Seats", f"Number of available seats on train {train_num} on {date} in {coach_type} class: {value}")
            popup_window.destroy()

        self.train_treeview.bind("<Button-1>", on_train_click)

    
    def display_trains(self):
        # Get the values from the entry boxes and dropdown menu
        source_station = self.source_station_entry.get()
        destination_station = self.destination_station_entry.get()
        # print(self.day_of_week.get())
        date_string=self.day_of_week_entry.get()
        
        try:
            date_string = datetime.datetime.strptime(date_string, "%d-%m-%Y")
        except ValueError:
            messagebox.showerror("Error", "Invalid date format. Please use DD-MM-YYYY")
            return
        day_week = date_string.strftime("%A")

        
        # # print(date_string)

        # # Extract the day of the week from the datetime object using strftime
        # day, month, year = map(int, date_string.split('-'))

        # day_week = calendar.day_name[calendar.weekday(year, month, day)]

        # # print(day_week)  # Output: Wednesday
        day_of_week = ["Sunday", "Saturday", "Friday","Thursday","Wednesday","Tuesday","Monday"   ].index(day_week)

        # Execute the query and display the results
        try:
            query = f"SELECT * FROM TrainsBtwStns('{source_station}', '{destination_station}', '{day_of_week}');"
            results = db.execute_dql_commands(query)
            self.train_treeview.delete(*self.train_treeview.get_children())
            for row in results:
                row_list = list(row)
                for i in range(4, 9):
                    if isinstance(row_list[i], time):
                        row_list[i] = row_list[i].strftime("%H:%M")
                    elif row_list[i] is None:
                        row_list[i] = 'N/A'

                # Convert integer to binary and pad to 7 digits
                binary = bin(row_list[3])[2:].zfill(7)

                # Create a list of days of the week in order
                days_of_week = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

                # Create a list of selected days based on the binary string
                selected_days = [days_of_week[i] for i in range(7) if binary[i] == '1']

                # Join the selected days into a comma-separated string
                days_string = ', '.join(selected_days)
                if binary=='1111111':
                    days_string='All days'
                row_list[3]=days_string
                # Print the string of selected days
                #print(days_string)
                self.train_treeview.insert('', END, values=row_list)
        except:
            print('NOT WORKING')

    def logout(self):
        self.isLoggedIn = False
        self.userId = None
        self.main_menu_frame.destroy()
        self.main_page()
        
    def login_page(self):
        # Clear the main menu frame
        self.main_menu_frame.destroy()

        # Create a frame for the login page
        self.login_frame = Frame(self.master)
        self.login_frame.pack(pady=50)
        Label(self.login_frame, text="Login Page", font=("Helvetica", 20)).pack(side=TOP, pady=20)

        # Create a username label and entry box
        Label(self.login_frame, text="Username", font=("Helvetica", 16)).pack(pady=10)
        self.username_entry = Entry(self.login_frame, font=("Helvetica", 16))
        self.username_entry.pack(pady=10)

        # Create a password label and entry box
        Label(self.login_frame, text="Password", font=("Helvetica", 16)).pack(pady=10)
        self.password_entry = Entry(self.login_frame, font=("Helvetica", 16), show="*")
        self.password_entry.pack(pady=10)

        # Create a button to submit the login information
        Button(self.login_frame, text="Login", font=("Helvetica", 16), command=self.login).pack(pady=10)

        #Button to go back to the home page
        Button(self.login_frame, text="Go Back", font=("Helvetica", 16), command=lambda: (self.login_frame.destroy(), self.main_page())).pack(pady=10)
        
    def login(self):
        # Get the values from the entry boxes
        username = self.username_entry.get()
        password = self.password_entry.get()

        # TODO: Implement login functionality
        query = f"SELECT COUNT(*) FROM new_user WHERE user_id={username} AND password='{password}'"
        results = db.execute_dql_commands(query)
        x = list(results)
        value = x[0][0]
        # print(x)
        if value==1:
            self.userId=username
            self.isLoggedIn=True
            # Show a message box to indicate successful login
            messagebox.showinfo("Success", "Login successful.")
            self.login_frame.destroy()
            self.main_page()
        else:
            messagebox.showinfo("Failure", "Incorrect credentials!")
        
    def signup_page(self):
        # Clear the main menu frame
        self.main_menu_frame.destroy()

        # Create a frame for the Register page
        self.signup_frame = Frame(self.master)
        self.signup_frame.pack(pady=50)
        Label(self.signup_frame, text="Register Page", font=("Helvetica", 20)).pack(side=TOP, pady=20)

        # Create a username label and entry box
        Label(self.signup_frame, text="Username (integer only)", font=("Helvetica", 16)).pack(pady=3)
        self.username_entry_signup_frame = Entry(self.signup_frame, font=("Helvetica", 16))
        self.username_entry_signup_frame.pack(pady=3)

        # Create a password label and entry box
        Label(self.signup_frame, text="Password", font=("Helvetica", 16)).pack(pady=3)
        self.password_entry_signup_frame = Entry(self.signup_frame, font=("Helvetica", 16), show="*")
        self.password_entry_signup_frame.pack(pady=3)
        
        # Create a name label and entry box
        Label(self.signup_frame, text="Name", font=("Helvetica", 16)).pack(pady=3)
        self.name_entry_signup_frame = Entry(self.signup_frame, font=("Helvetica", 16))
        self.name_entry_signup_frame.pack(pady=3)

        # Create a email label and entry box
        Label(self.signup_frame, text="Email", font=("Helvetica", 16)).pack(pady=3)
        self.email_entry_signup_frame = Entry(self.signup_frame, font=("Helvetica", 16))
        self.email_entry_signup_frame.pack(pady=3)
        
        # Create a phno label and entry box
        Label(self.signup_frame, text="phno", font=("Helvetica", 16)).pack(pady=3)
        self.phno_entry_signup_frame = Entry(self.signup_frame, font=("Helvetica", 16))
        self.phno_entry_signup_frame.pack(pady=3)

        # Create a aadhar label and entry box
        Label(self.signup_frame, text="aadhar", font=("Helvetica", 16)).pack(pady=3)
        self.aadhar_entry_signup_frame = Entry(self.signup_frame, font=("Helvetica", 16))
        self.aadhar_entry_signup_frame.pack(pady=3)
        
        # Create a address label and entry box
        Label(self.signup_frame, text="address", font=("Helvetica", 16)).pack(pady=3)
        self.address_entry_signup_frame = Entry(self.signup_frame, font=("Helvetica", 16))
        self.address_entry_signup_frame.pack(pady=3)

        # Create a dob label and entry box
        Label(self.signup_frame, text="dob", font=("Helvetica", 16)).pack(pady=3)
        self.dob_entry_signup_frame = Entry(self.signup_frame, font=("Helvetica", 16))
        self.dob_entry_signup_frame.pack(pady=3)

        # Create a button to submit the Register information
        Button(self.signup_frame, text="Register", font=("Helvetica", 16), command=self.signup).pack(pady=3)

        #Button to go back to the home page
        Button(self.signup_frame, text="Go Back", font=("Helvetica", 16), command=lambda: (self.signup_frame.destroy(), self.main_page())).pack(pady=3)
    
    def signup(self):
        # Get the values from the entry boxes
        username = self.username_entry_signup_frame.get()
        password = self.password_entry_signup_frame.get()
        name = self.name_entry_signup_frame.get()
        email = self.email_entry_signup_frame.get()
        phno = self.phno_entry_signup_frame.get()
        aadhar = self.aadhar_entry_signup_frame.get()
        address = self.address_entry_signup_frame.get()
        dob = self.dob_entry_signup_frame.get()
        try:
            dob = datetime.datetime.strptime(dob, "%d-%m-%Y")
        except ValueError:
            messagebox.showerror("Error", "Invalid date format. Please use DD-MM-YYYY")
            return

        query = f"SELECT COUNT(*) FROM new_user WHERE user_id={username}"
        results = db.execute_dql_commands(query)
        x = list(results)
        value = x[0][0]
        # print(x)
        if value==0:
            # print("not already existent username, trying to insert")
            query = f"INSERT INTO new_user VALUES ({username},'{name}','{email}',{phno},{aadhar},'{address}','{dob}','{password}');"
            results = db.execute_ddl_and_dml_commands(query)
            # print("insert attempted")
            
            query1 = f"SELECT COUNT(*) FROM new_user WHERE user_id={username}"
            results1 = db.execute_dql_commands(query1)
            x1 = list(results1)
            value1 = x1[0][0]
            if value1==1:
                self.userId=username
                self.isLoggedIn=True
                # Show a message box to indicate successful login
                messagebox.showinfo("Success", "Sign up successful.")
                self.signup_frame.destroy()
                self.main_page()
            else:
                print("unexpected error occurred in inserting")
                messagebox.showinfo("Error", "Sign up failed, see terminal.")
        else:
            messagebox.showinfo("Failure", "Such a username is already registered!")
        
    def reserve_tickets_page(self):

        # Clear the main menu frame
        self.main_menu_frame.destroy()

        # Create a frame to hold the input widgets
        self.input_frame = Frame(self.master)
        self.input_frame.pack(side=LEFT, padx=10, pady=10)
        self.input_frameRT1 = Frame(self.master)
        self.input_frameRT1.pack(side=RIGHT, padx=50, pady=10)

        # Create labels and entry boxes for all the required information
        self.name_label= Label(self.input_frame, text="Reserve Tickets", font=("Helvetica", 20))
        self.name_label.grid(row=0, column=1)
        
        self.tno_label = Label(self.input_frame, text="Train Number:")
        self.tno_label.grid(row=1, column=0)
        self.tno_entry = Entry(self.input_frame)
        self.tno_entry.grid(row=1, column=1)

        self.src_label = Label(self.input_frame, text="Source Station Code:")
        self.src_label.grid(row=2, column=0)
        self.src_entry = Entry(self.input_frame)
        self.src_entry.grid(row=2, column=1)

        self.dst_label = Label(self.input_frame, text="Destination Station Code:")
        self.dst_label.grid(row=3, column=0)
        self.dst_entry = Entry(self.input_frame)
        self.dst_entry.grid(row=3, column=1)
        
        # self.doj_label= Label(self.input_frame, text="Date of journey (DD-MM-YYYY):")
        # self.doj_label.grid(row=3, column=0)
        # self.doj_entry = Entry(self.input_frame)
        # self.doj_entry.grid(row=3, column=1)
        
        self.doj_label = Label(self.input_frame, text="Date of journey (DD-MM-YYYY):")
        self.doj_label.grid(row=4, column=0)

        # Create a DateEntry widget for selecting the date of journey
        self.doj_entry = DateEntry(self.input_frame, date_pattern="dd-mm-yyyy")
        self.doj_entry.grid(row=4, column=1)

        # Create a label and dropdown menu for the day of the week
        self.ctyp_entry_label = Label(self.input_frame, text="Coach Type:")
        self.ctyp_entry_label.grid(row=5, column=0)
        self.ctyp_entry = StringVar()
        self.ctyp_entry_rolldown = OptionMenu(self.input_frame, self.ctyp_entry, *["CC", "3AC"])
        self.ctyp_entry_rolldown.grid(row=5, column=1)
        
        # self.pass_label= Label(self.input_frame, text="Passenger IDs (comma-separated):")
        # self.pass_label.grid(row=7, column=0)
        # self.pass_entry = Entry(self.input_frame)
        # self.pass_entry.grid(row=7, column=1)
        # self.pass_entry.config(state="disabled")
        
        self.pass_sel_label= Label(self.input_frameRT1, text="Select passengers:")
        self.pass_sel_label.grid(row=1, column=0)
        self.toBeBooked = Listbox(self.input_frameRT1,selectmode='multiple',exportselection=0)
        self.toBeBooked.grid(row=0, column=1)
        
        query=f'SELECT pass_id,name,age,gender from passenger where user_id={self.userId};'
        # print(query)
        res=db.execute_dql_commands(query)
        if res is not None:
            x=list(res)
            # print(x)
            for i,eachEntry in enumerate(x):
                self.toBeBooked.insert(i,eachEntry)
        
        # Create a button to execute the query
        self.reserve_button = Button(self.input_frame, text="Reserve Seats", command=self.reserve_seat)
        self.reserve_button.grid(row=8, column=0, columnspan=2, pady=10)
        
        # self.result_label= Label(self.input_frame, text="PNR No:")
        # self.result_label.grid(row=9, column=0)
        # self.result_output = Entry(self.input_frame)
        # self.result_output.grid(row=9, column=1)
        
        #Button to go back to the home page
        self.reserve_button = Button(self.input_frame, text="Go Back", command=lambda: (self.input_frame.destroy(),self.input_frameRT1.destroy(),self.main_page()))
        self.reserve_button.grid(row=10, column=0, columnspan=2, pady=10)
        
        
    def reserve_seat(self):
        tno = self.tno_entry.get()
        src = self.src_entry.get()
        dst = self.dst_entry.get()
        doj = self.doj_entry.get()
        c_typ = self.ctyp_entry.get()
        usr_id = self.userId
        trxn_id = random.randint(100,1000000)
        # pass_ids = self.pass_entry.get()
        ###
        pass_ids = None
        selected_text_list = [self.toBeBooked.get(i) for i in self.toBeBooked.curselection()]
        # print(selected_text_list)
        numbers = [s.split(',')[0].strip('()') for s in selected_text_list]
        pass_ids = ','.join(numbers)
        # print(pass_ids)
        # for eachsel in selected_text_list:
        #     eachsel=','.split(eachsel)
        #     print(eachsel)
        #     print(eachsel[1])
        ###
        
        if not tno or not src or not dst or not doj or not c_typ or not usr_id or not trxn_id or not pass_ids:
            messagebox.showerror("Error", "Please enter all required fields")
            return
        try:
            doj = datetime.datetime.strptime(doj, "%d-%m-%Y")
        except ValueError:
            messagebox.showerror("Error", "Invalid date format. Please use DD-MM-YYYY")
            return
        query1 = f"CALL reserve_seat('{tno}', '{src}', '{dst}', '{doj}', '{c_typ}', {usr_id}, {trxn_id}, '{pass_ids}');"
        values = {"tno": tno, "src": src, "dst": dst, "doj": doj, "c_typ": c_typ, "usr_id": usr_id, "trxn_id": trxn_id, "pass_ids": pass_ids}
        # try:
        prevquery="SELECT booking_id from booking order by booking_date desc limit 1;"
        prevres=db.execute_dql_commands(prevquery)
        prevx=list(prevres)
        prevval=None
        try:
            prevval=prevx[0][0]
        except:
            pass
        db.execute_ddl_and_dml_commands(query1, values)
        querynew="SELECT booking_id from booking order by booking_date desc limit 1;"
        nextres=db.execute_dql_commands(querynew)
        nextx=list(nextres)
        nextval=nextx[0][0]
        # print(prevval)
        # print(nextval)
        if(prevval!=nextval):
            messagebox.showinfo("Success", "Reservation successful.")
            # Generate a PDF file of the ticket details
            query = f"SELECT train_name FROM train WHERE train_no={tno} ;"
            res=db.execute_dql_commands(query)
            x=list(res)
            TRainName = x[0][0]
            query = f"SELECT fare FROM booking WHERE txn_id={trxn_id} ;"
            res=db.execute_dql_commands(query)
            x=list(res)
            FAre = x[0][0]
            query = f"SELECT booking_date FROM booking WHERE txn_id={trxn_id} ;"     
            res=db.execute_dql_commands(query)
            x=list(res)
            Book_date = x[0][0]

            query = "SELECT * FROM pass_tkt ORDER BY pnr_no DESC LIMIT 1 ;"     # Major bug here fixed
            res=db.execute_dql_commands(query)
            x=list(res)
            pnrno=x[0][0]
            query = f"SELECT * FROM station WHERE stn_id=\'{src}\' OR stn_id=\'{dst}\';"     # Major bug here fixed
            # print(".\n",query)
            res=db.execute_dql_commands(query)
            x=list(res)
            # print(x,".")
            
            stnNameDict=dict()
            for xi in x:
                stnNameDict[xi[0]]=xi[1]
            
            
            query = f"SELECT pass_id,coach_no,seat_no FROM pass_tkt WHERE pnr_no={pnrno} AND \"isConfirmed\"='CNF';"
            # print(".\n",query)
            res=db.execute_dql_commands(query)
            X=list(res)
            # print(x)
            # print(".")
            userPassDict = dict()
            query = f"SELECT * FROM passenger WHERE user_id = {self.userId};;"
            # print(".\n",query)
            res=db.execute_dql_commands(query)
            x1=list(res)
            for xi in x1:
                userPassDict[xi[0]]=[xi[1],xi[2],xi[3]]
            
            ticket_filename = f"ticket_{nextval}.pdf"
            c = canvas.Canvas(ticket_filename)
            c.setFont("Helvetica-Bold", 20)
            c.drawString(150, 800, "Electronic Reservation Slip (ERS)")
            c.setFont("Helvetica", 12)
            # c.drawString(250, 780, "---------")
            c.setFont("Helvetica-Bold", 13)
            c.drawString(100, 730, f"Booked From")
            c.setFont("Helvetica", 12)
            
            c.drawString(100, 710, f"{stnNameDict[src]} ({src})")
            c.setFont("Helvetica-Bold", 13)
            c.drawString(400, 730, f"Booked To")
            c.setFont("Helvetica", 12)
            
            c.drawString(400, 710, f"{stnNameDict[dst]} ({dst})")
            c.drawString(100, 670, f"PNR NO: {pnrno}")
            c.drawString(100, 650, f"Train: [{tno}] {TRainName}")
            # c.drawString(100, 690, f"Destination Station: {dst}")
            c.drawString(100, 630, f"Coach Type: {c_typ}")
            c.drawString(100, 610, f"Date of Journey: {doj.strftime('%d-%m-%Y')}")
            # c.drawString(100, 610, f"User ID: {usr_id}")
            c.drawString(100, 590, f"Transaction ID: {trxn_id}")
            # c.drawString(100, 590, f"Passenger IDs: {pass_ids}")
            x = 100
            y = 550
            tab_width = 80
            c.setFont("Helvetica-Bold", 13)
            c.drawString(x, y, " Pid ")
            x += tab_width*0.75
            c.drawString(x, y, " Name ")
            x += tab_width*1.2
            c.drawString(x, y, " Age ")
            x += tab_width*0.65
            c.drawString(x, y, " Gender ")
            x += tab_width
            c.drawString(x, y, " Coach num ")
            x += tab_width
            c.drawString(x, y, " Seat ")
            
            c.setFont("Helvetica", 12)
            curY = y
            for i,xi in enumerate(X):
                pd,cn,sn=xi
                x = 100
                y = (530-20*i)
                curY = y
                
                c.drawString(x, y, f" {pd} ")
                x += tab_width*0.75
                c.drawString(x, y, f" {userPassDict[pd][0]} ")
                x += tab_width*1.2
                c.drawString(x, y, f" {userPassDict[pd][1]} ")
                x += tab_width*0.65
                c.drawString(x, y, f" {userPassDict[pd][2]} ")
                x += tab_width
                c.drawString(x, y, f" {cn} ")
                x += tab_width
                SEAT_TYPE = None
                if c_typ=='CC':
                    if sn==2:
                        SEAT_TYPE="Middle"
                    elif sn==3:
                        SEAT_TYPE="Aisle"
                    else:
                        SEAT_TYPE="Window"
                else:
                    if sn==2:
                        SEAT_TYPE="Middle"
                    elif sn==3:
                        SEAT_TYPE="Upper"
                    else:
                        SEAT_TYPE="Lower"
                c.drawString(x, y, f" {sn} / {SEAT_TYPE}")
            
            # FAre
            y = curY
            y = (curY-40)
            c.drawString(100, y, f"Fare: Rs.{FAre}.00")
            y = (y-20)
            c.drawString(100, y, f"Booking Date: {Book_date}")
            c.save()
            messagebox.showinfo("Success", f"Ticket details saved to {ticket_filename}")
            if platform.system() == "Windows":
                subprocess.Popen([ticket_filename], shell=True)
            elif platform.system() == "Darwin":
                subprocess.Popen(["open", ticket_filename])
            else:
                subprocess.Popen(["xdg-open", ticket_filename])
        else:
            messagebox.showinfo("Failure", "Reservation unsuccessful. Check availability first")
    
    
    def cancel_seat_page(self):

        # Clear the main menu frame
        self.main_menu_frame.destroy()

        # Create a frame to hold the input widgets
        self.input_frame = Frame(self.master)
        self.input_frame.pack(side=TOP, padx=10, pady=10)
        self.train_list_label = Label(self.input_frame, text="   Cancel Tickets", font=("Helvetica Bold", 24))
        self.train_list_label.pack(padx=50, pady=50)
        
        # Create a frame to hold the select to cancel pass widgets
        self.input_frameRT = Frame(self.master)
        self.input_frameRT.pack( padx=50, pady=50)
        
        self.pnr_no_labelA= Label(self.input_frameRT, text="                   Select passengers\n                     to be cancelled:", font="Helvetica 14 bold")
        self.pnr_no_labelA.grid(row=0, column=3)
        self.toBeCancelled = Listbox(self.input_frameRT,selectmode='multiple',exportselection=0)
        self.toBeCancelled.grid(row=0, column=4)
        
        self.pnr_no_label= Label(self.input_frameRT, text="PNR No:", font="Helvetica 14 bold")
        self.pnr_no_label.grid(row=0, column=0)

        self.PNRtoBeCancelled = Listbox(self.input_frameRT,selectmode='single',exportselection=0)
        self.PNRtoBeCancelled.grid(row=0, column=1)
        
        query=f'SELECT distinct pnr_no from booking natural join pass_tkt where pass_tkt."isConfirmed"=\'CNF\' and user_id={self.userId};'
        # print(query)
        res=db.execute_dql_commands(query)
        if res is not None:
            x=list(res)
            # print(x)
            for i,eachEntry in enumerate(x):
                self.PNRtoBeCancelled.insert(i,eachEntry)
                
        self.btnNext = None
        self.cancel_button=None
        def execnext():
            self.PNR_tobecancelled = None
            
            ####
            selected_text_list1 = [self.PNRtoBeCancelled.get(i) for i in self.PNRtoBeCancelled.curselection()]
            # print(selected_text_list1)
            numbers = [s.split(',')[0].strip('()') for s in selected_text_list1]
            self.PNR_tobecancelled = ','.join(numbers)
            # print(self.PNR_tobecancelled)
            ####
            if self.PNR_tobecancelled is None:
                return
            
            query=f'select distinct(p.pass_id), pas.name from booking as b natural join pass_tkt as p join passenger as pas ON p.pass_id = pas.pass_id where p."isConfirmed"=\'CNF\' and pas.user_id={self.userId} and pnr_no={self.PNR_tobecancelled};'
            # query=f'select distinct pass_id from booking natural join pass_tkt where pass_tkt."isConfirmed"=\'CNF\' and user_id={self.userId} and pnr_no={self.PNR_tobecancelled};'
            # print(query)
            res=db.execute_dql_commands(query)
            if res is not None:
                x=list(res)
                # print(x)
                for i,eachEntry in enumerate(x):
                    self.toBeCancelled.insert(i,eachEntry)
                self.btnNext.config(state="disabled")
                self.cancel_button.config(state="active")
            pass
        
        self.btnNext = Button(self.input_frameRT,text="Next", font="Helvetica 12 bold",command=execnext)
        
        self.btnNext.grid(row=2, column=2, columnspan=2, pady=10)
        
        # Create a button to execute the query
        self.cancel_button = Button(self.input_frameRT, text="Cancel seats", font="Helvetica 12 bold", command=self.cancel_seat)
        self.cancel_button.grid(row=5, column=2, columnspan=2, pady=10)
        self.cancel_button.config(state="disabled")

        #Button to go back to the home page
        self.back_button = Button(self.input_frameRT, text="Go Back", font="Helvetica 12 bold", command=lambda: (self.input_frame.destroy(),self.input_frameRT.destroy(), self.main_page()))
        self.back_button.grid(row=6, column=2, columnspan=2, pady=10)
        
        
    def cancel_seat(self):
        # pnr_no = self.pnr_no_entry.get()
        usr_id = self.userId
        # pass_ids = self.pass_entry.get()
        pnr_no = self.PNR_tobecancelled
        
        pass_ids = None
        selected_text_list = [self.toBeCancelled.get(i) for i in self.toBeCancelled.curselection()]
        # print(selected_text_list)
        numbers = [s.split(',')[0].strip('()') for s in selected_text_list]
        pass_ids = ','.join(numbers)
        # print(pass_ids)
        
        if not pnr_no or not usr_id or not pass_ids:
            messagebox.showerror("Error", "Please enter all required fields")
            return
        query1 = f"CALL cancel_seat('{pnr_no}', {usr_id}, '{pass_ids}');"
        values = {"pnr_no": pnr_no,"usr_id": usr_id, "pass_ids": pass_ids}
        
        prevquery=f'SELECT "isConfirmed" from pass_tkt where pnr_no={pnr_no};'
        prevres=db.execute_dql_commands(prevquery)
        prevx=list(prevres)
        prevval=None
        try:
            prevval=prevx[0][0]
        except:
            pass
        db.execute_ddl_and_dml_commands(query1, values)
        newquery=f'SELECT "isConfirmed" from pass_tkt where pnr_no={pnr_no};'
        nextres=db.execute_dql_commands(newquery)
        nextx=list(nextres)
        nextval=nextx[0][0]
        # print(prevval)
        # print(nextval)
        self.cancel_button.config(state="disabled")
        if(prevx!=nextx):
            messagebox.showinfo("Success", "Cancelation successful.")
        else:
            messagebox.showinfo("Failure", "Cancelation unsuccessful. Check pnr number and status of seats first")
        
    def passenger_registration_page(self):

        # Clear the main menu frame
        self.main_menu_frame.destroy()

        # Create a frame to hold the passenger registration
        self.passenger_reg_frame = Frame(self.master)
        self.passenger_reg_frame.pack(side=LEFT,padx=10, pady=10)
        
        self.name_label= Label(self.passenger_reg_frame, text="Passenger Registration", font=("Helvetica", 20))
        self.name_label.grid(row=0, column=1)
        
        self.name_label= Label(self.passenger_reg_frame, text="Name:")
        self.name_label.grid(row=1, column=0)
        self.name_entry = Entry(self.passenger_reg_frame)
        self.name_entry.grid(row=1, column=1)
        
        self.age_label= Label(self.passenger_reg_frame, text="Age:")
        self.age_label.grid(row=2, column=0)
        self.age_entry = Entry(self.passenger_reg_frame)
        self.age_entry.grid(row=2, column=1)
        
        # Create a label and dropdown menu for choosing the gender
        self.gender_label = Label(self.passenger_reg_frame, text="Gender:")
        self.gender_label.grid(row=3, column=0)
        self.gender = StringVar()
        self.gender_rolldown = OptionMenu(self.passenger_reg_frame, self.gender, *["M", "F","Other"])
        self.gender_rolldown.grid(row=3, column=1)
        
        self.nationality_label= Label(self.passenger_reg_frame, text="Nationality:")
        self.nationality_label.grid(row=4, column=0)
        self.nationality_entry = Entry(self.passenger_reg_frame)
        self.nationality_entry.grid(row=4, column=1)
        
        # Create a label and dropdown menu for choosing the concession type
        self.conces_typ_label = Label(self.passenger_reg_frame, text="Concession Type:")
        self.conces_typ_label.grid(row=5, column=0)
        self.conces_typ = StringVar()
        self.conces_typ_rolldown = OptionMenu(self.passenger_reg_frame, self.conces_typ, *["senior_ctzn", "armed_forces","student","other"])
        self.conces_typ_rolldown.grid(row=5, column=1)
        
        # Create a button to execute the query
        self.create_user_button = Button(self.passenger_reg_frame, text="Create User", command=self.passenger_registration)
        self.create_user_button.grid(row=6, column=0, columnspan=2, pady=10)
        
        #Button to go back to the home page
        self.reserve_button = Button(self.passenger_reg_frame, text="Go Back", command=lambda: (self.passenger_reg_frame.destroy(), self.main_page()))
        self.reserve_button.grid(row=7, column=0, columnspan=2, pady=10)
            
    def passenger_registration(self):
        name = self.name_entry.get()
        age = self.age_entry.get()
        gender = self.gender.get()
        nationality =self.nationality_entry.get()
        conces_typ = self.conces_typ.get()        
        
        pass_query=f'SELECT count(*) from passenger;'
        count_res=db.execute_dql_commands(pass_query)
        x = list(count_res)

        pass_id=x[0][0]+5
        
        if not name or not age or not gender or not nationality or not conces_typ or not pass_id:
            messagebox.showerror("Error", "Please enter all required fields")
            return
        if conces_typ=='senior_ctzn' and int(age)<=60:
            messagebox.showerror("Error", f"Passenger with age {age} is ineligible for senior_ctzn concession.")
            return
        query = f"SELECT COUNT(*) FROM passenger WHERE name='{name}' AND age='{age}' AND gender='{gender}' AND nationality='{nationality}' AND user_id='{self.userId}';"
        results = db.execute_dql_commands(query)
        x = list(results)
        value = x[0][0]
        # print(x)
        # print(value)
        if value==0:
            # print("new passenger, trying to insert")
            query = f"INSERT INTO passenger VALUES ({pass_id},'{name}', {age}, '{gender}','{nationality}','{conces_typ}',{self.userId});"
            # print(query)
            try:
                db.execute_ddl_and_dml_commands(query)
            except:
                print('Error')
                
            # print("Insert attempted")
            query1 = f"SELECT COUNT(*) FROM passenger WHERE name='{name}' AND age={age} AND gender='{gender}' AND nationality='{nationality}' AND user_id={self.userId};"
            results1 = db.execute_dql_commands(query1)
            x1 = list(results1)
            value1 = x1[0][0]
            
            if value1==1:
                
                # Show a message box to indicate successful login
                messagebox.showinfo("Success", "Passenger registration successful.")
                self.passenger_reg_frame.destroy()
                self.main_page()
            else:
                print("unexpected error occurred in inserting")
                messagebox.showinfo("Error", "Passenger registration failed, see terminal.")
        else:
            messagebox.showinfo("Failure", "Such a passenger is already registered!")
        
def main():
    root=Tk()
    root.title("railway-management-system")
    screen_width = root.winfo_screenwidth()
    screen_height = root.winfo_screenheight()
    scrSizeStr=str(int(screen_width))+'x'+str(int(screen_height))
    root.geometry(scrSizeStr)
    app = RailwayManagementSystemGUI(root)
    root.mainloop()


if __name__ == '__main__':
    main()
