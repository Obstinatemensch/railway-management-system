from datetime import time
from tkinter import *
from tkinter import messagebox
import sqlalchemy
from sqlalchemy.engine import create_engine
from sqlalchemy.sql import text

root = Tk()
root.title("railway-management-system")
screen_width = root.winfo_screenwidth()
screen_height = root.winfo_screenheight()
scrSizeStr=str(int(screen_width))+'x'+str(int(screen_height))
root.geometry(scrSizeStr)


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
            print('Command executed successfully.')
        except Exception as err:
            trans.rollback()
            print(f'Failed to execute ddl and dml commands -- {err}')

USER_NAME = 'postgres'
PASSWORD = 'postgres'
PORT = 5432
DATABASE_NAME = 'railwaymanagementsys'
HOST = 'localhost'

db = PostgresqlDB(user_name=USER_NAME,
                    password=PASSWORD,
                    host=HOST,port=PORT,
                    db_name=DATABASE_NAME)
engine = db.engine

class RailwayManagementSystemGUI:
    def __init__(self, master):
        # Initialize the GUI window
        self.master = master
        self.master.title("Railway Management System")
        
        # Create a frame for the main menu
        self.main_menu_frame = Frame(self.master)
        self.main_menu_frame.pack(pady=50)
        Label(self.main_menu_frame, text="Welcome to Railway Management System", font=("Helvetica", 20)).pack(side=TOP, pady=20)

        # Button to display trains between stations
        Button(self.main_menu_frame, text="Trains Between Stations", font=("Helvetica", 16), command=self.trains_between_stations).pack(pady=10)

        # Button to login page
        Button(self.main_menu_frame, text="Login", font=("Helvetica", 16), command=self.login_page).pack(pady=10)

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

        # Create a label and dropdown menu for the day of the week
        self.day_of_week_label = Label(self.input_frame, text="Day of Week:")
        self.day_of_week_label.grid(row=2, column=0)
        self.day_of_week = StringVar()
        self.day_of_week_dropdown = OptionMenu(self.input_frame, self.day_of_week, *["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
        self.day_of_week_dropdown.grid(row=2, column=1)

        # Create a button to execute the query
        self.execute_button = Button(self.input_frame, text="Find Trains", command=self.display_trains)
        self.execute_button.grid(row=3, column=0, columnspan=2, pady=10)

        # Create a frame to hold the output widget
        self.output_frame = Frame(self.master)
        self.output_frame.pack(side=RIGHT, padx=10, pady=10)

        # Create a label for the output widget
        self.train_list_label = Label(self.output_frame, text="Trains Between Stations:")
        self.train_list_label.pack()

        # Create a Listbox widget for the output
        self.train_listbox = Listbox(self.output_frame, width=50)
        self.train_listbox.pack()

    # # works well, but o/p in terminal
    # def display_trains(self):
    #     # Get the values from the entry boxes and dropdown menu
    #     source_station = self.source_station_entry.get()
    #     destination_station = self.destination_station_entry.get()
    #     day_of_week = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].index(self.day_of_week.get())

    #     # Execute the query and display the results
    #     query = f"SELECT * FROM TrainsBtwStns('{source_station}', '{destination_station}', {day_of_week});"
    #     results = db.execute_dql_commands(query)
    #     for row in results:
    #         row_list = list(row)
    #         for i in range(4, 8):
    #             if isinstance(row_list[i], time):
    #                 row_list[i] = row_list[i].strftime("%H:%M")
    #             elif row_list[i] is None:
    #                 row_list[i] = 'N/A'
    #         print(tuple(row_list))
    
    def display_trains(self):
        # Get the values from the entry boxes and dropdown menu
        source_station = self.source_station_entry.get()
        destination_station = self.destination_station_entry.get()
        day_of_week = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].index(self.day_of_week.get())

        # Execute the query and display the results
        query = f"SELECT * FROM TrainsBtwStns('{source_station}', '{destination_station}', {day_of_week});"
        results = db.execute_dql_commands(query)
        self.train_listbox.delete(0, END)
        for row in results:
            row_list = list(row)
            for i in range(4, 8):
                if isinstance(row_list[i], time):
                    row_list[i] = row_list[i].strftime("%H:%M")
                elif row_list[i] is None:
                    row_list[i] = 'N/A'
            self.train_listbox.insert(END, tuple(row_list))





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

    def login(self):
        # Get the values from the entry boxes
        username = self.username_entry.get()
        password = self.password_entry.get()

        # TODO: Implement login functionality

        # Show a message box to indicate successful login
        messagebox.showinfo("Success", "Login successful.")

def main():
    root = Tk()
    app = RailwayManagementSystemGUI(root)
    root.mainloop()


if __name__ == '__main__':
    main()
