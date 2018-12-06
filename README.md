
# Data Record Object

## Oracle PL/SQL solution to handle tables and rows by general way

## Why?

Because I wanted to play a little with Oracle Object Type feature.

...and for example using this general solution we can not get compilation error when we are referring to not existing table or column.

So, **T_DATA_RECORD** is a general object with native data types as **NUMBER**, **DATE** and **VARCHAR**
It can **READ**, **WRITE** (insert or update), **DELETE** and **PRINT** any record and any table.


## How?

The code is very simple, so do not I think it needs for further explanation.
But here is a simpe example for usage: ( there is not commit nor rollback in the object!)

    declare

        -- USERS is the table name and TOTHF is the PK
        V_USER        T_DATA_RECORD := new T_DATA_RECORD ( 'USERS', 'TOTHF' );   

        -- a copy of V_USER
        V_USER_NEW    T_DATA_RECORD := new T_DATA_RECORD ( V_USER );  

    begin

        V_USER.SET_VALUE('REMARK','Testing it');
        V_USER.WRITE_DATA;

        V_USER_NEW.PRIMARY_KEY_VALUE := 'DOG';
        V_USER_NEW.WRITE_DATA;

        dbms_output.put_line( V_USER.LAST_OPERATION );
        dbms_output.put_line( V_USER.LAST_ERRCODE   );
        dbms_output.put_line( V_USER.LAST_ERRMSG    );
        V_USER.PRINT;

        dbms_output.put_line( V_USER_NEW.LAST_OPERATION );
        dbms_output.put_line( V_USER_NEW.LAST_ERRCODE   );
        dbms_output.put_line( V_USER_NEW.LAST_ERRMSG    );
        V_USER_NEW.PRINT;

    end;

