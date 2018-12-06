


CREATE OR REPLACE FUNCTION F_PK ( I_TABLE_NAME   in varchar2 
                                , I_SCHEMA_NAME  in varchar2 := null
                                ) return varchar2 deterministic is
    L_PK     varchar2 ( 300 );
begin
    if I_SCHEMA_NAME is null then
        select COLUMN_NAME
          into L_PK
          from USER_CONSTRAINTS  UC
             , USER_CONS_COLUMNS DBC
         where UC.CONSTRAINT_TYPE  = 'P'
           and DBC.CONSTRAINT_NAME = UC.CONSTRAINT_NAME
           and DBC.TABLE_NAME      = I_TABLE_NAME;
    else
        select COLUMN_NAME
          into L_PK
          from ALL_CONSTRAINTS  AC
             , ALL_CONS_COLUMNS DBC
         where AC.CONSTRAINT_TYPE  = 'P'
           and DBC.CONSTRAINT_NAME = AC.CONSTRAINT_NAME
           and DBC.TABLE_NAME      = I_TABLE_NAME
           and AC.OWNER            = DBC.OWNER
           and AC.OWNER            = I_SCHEMA_NAME;
    end if;
    return L_PK;
exception when others then
    return null;
end;

/


/*
drop type T_DATA_RECORD;
drop type T_DATA_FIELD_DATE_LIST;
drop type T_DATA_FIELD_NUMERIC_LIST;
drop type T_DATA_FIELD_STRING_LIST;
*/

-- Basic types
create or replace type T_DATA_FIELD_DATE    as object( NAME varchar2(300), VALUE date            );
/

create or replace type T_DATA_FIELD_NUMERIC as object( NAME varchar2(300), VALUE number          );
/

create or replace type T_DATA_FIELD_STRING  as object( NAME varchar2(300), VALUE varchar2(32000) );  
/

-- List of basic types
create or replace type T_DATA_FIELD_DATE_LIST    as table of T_DATA_FIELD_DATE;
/

create or replace type T_DATA_FIELD_NUMERIC_LIST as table of T_DATA_FIELD_NUMERIC;
/

create or replace type T_DATA_FIELD_STRING_LIST  as table of T_DATA_FIELD_STRING;
/




/* ************************************************************************ */
create or replace type T_DATA_RECORD as object
/* ************************************************************************ */
(

    --------------- 
    -- Attributes
    --------------- 

    SCHEMA_NAME         varchar2(300),  
    TABLE_NAME          varchar2(300),  
    PRIMARY_KEY_COLUMN  varchar2(300),  
    PRIMARY_KEY_VALUE   varchar2(300),  

    DATE_FIELDS         T_DATA_FIELD_DATE_LIST,
    NUMERIC_FIELDS      T_DATA_FIELD_NUMERIC_LIST,
    STRING_FIELDS       T_DATA_FIELD_STRING_LIST,

    LAST_OPERATION      varchar2(1),     -- select = 'S', insert = 'I', update='U', delete='D'
    LAST_ERRCODE        number,          -- null = no error was found
    LAST_ERRMSG         varchar2(2000),

    --------------- 
    -- Constructors
    --------------- 

    -- create a new empty instance
    constructor function T_DATA_RECORD return self as result,

    -- copy from an existing instance
    constructor function T_DATA_RECORD ( I_DATA_RECORD in T_DATA_RECORD ) return self as result,

    -- create and read it
    constructor function T_DATA_RECORD ( I_SCHEMA_NAME in varchar2,
                                         I_TABLE_NAME  in varchar2, 
                                         I_PRIMARY_KEY in varchar2 ) return self as result,

    -- use the current schema
    constructor function T_DATA_RECORD ( I_TABLE_NAME  in varchar2, 
                                         I_PRIMARY_KEY in varchar2 ) return self as result,
    ---------- 
    -- Methods
    ---------- 

    -- read it from the table
    member procedure READ_DATA,

    -- it will be insert or update
    member procedure WRITE_DATA,

    -- delete it from the table
    member procedure DELETE_DATA,

    -- set field value
    member procedure SET_VALUE(I_FIELD_NAME varchar2, I_VALUE date    ),
    member procedure SET_VALUE(I_FIELD_NAME varchar2, I_VALUE number  ),
    member procedure SET_VALUE(I_FIELD_NAME varchar2, I_VALUE varchar2),

    -- set field to null (exists but is null)
    member procedure SET_NULL (I_FIELD_NAME varchar2),

    -- is null? if the field does not exist return with null !
    member function  IS_NULL  (I_FIELD_NAME varchar2) return boolean,

    -- does the field exist?
    member function  EXIST    (I_FIELD_NAME varchar2) return boolean,

    -- remove field from field list
    member procedure REMOVE   (I_FIELD_NAME varchar2),

    -- get field value functions:
    member function GET_FIELD_TYPE   (I_FIELD_NAME varchar2) return varchar2,
    member function GET_DATE_VALUE   (I_FIELD_NAME varchar2) return date,
    member function GET_NUMERIC_VALUE(I_FIELD_NAME varchar2) return number,
    member function GET_STRING_VALUE (I_FIELD_NAME varchar2) return varchar2,

    -- write the record to the dbms_outpt:
    member procedure PRINT ( I_DEBUG_MESSAGE varchar2 default null) 

);
/


/* ************************************************************************ */
create or replace type body T_DATA_RECORD as 
/* ************************************************************************ */
 

    -- create a new empty object
    constructor function T_DATA_RECORD return self as result is
    begin
        self.SCHEMA_NAME        := null;
        self.TABLE_NAME         := null;
        self.PRIMARY_KEY_COLUMN := null;
        self.PRIMARY_KEY_VALUE  := null;
        self.DATE_FIELDS        := new T_DATA_FIELD_DATE_LIST   ();
        self.NUMERIC_FIELDS     := new T_DATA_FIELD_NUMERIC_LIST();
        self.STRING_FIELDS      := new T_DATA_FIELD_STRING_LIST ();
        return;
    end;

    -- copy from an existing instance
    constructor function T_DATA_RECORD ( I_DATA_RECORD in T_DATA_RECORD ) return self as result is
    begin
        self.SCHEMA_NAME        := I_DATA_RECORD.SCHEMA_NAME;
        self.TABLE_NAME         := I_DATA_RECORD.TABLE_NAME;
        self.PRIMARY_KEY_COLUMN := I_DATA_RECORD.PRIMARY_KEY_COLUMN;
        self.PRIMARY_KEY_VALUE  := null;
        self.DATE_FIELDS        := I_DATA_RECORD.DATE_FIELDS;
        self.NUMERIC_FIELDS     := I_DATA_RECORD.NUMERIC_FIELDS;
        self.STRING_FIELDS      := I_DATA_RECORD.STRING_FIELDS;
        return;
    end;

    -- create and read it
    constructor function T_DATA_RECORD ( I_SCHEMA_NAME in varchar2,
                                         I_TABLE_NAME  in varchar2, 
                                         I_PRIMARY_KEY in varchar2 ) return self as result is
    begin
        self.SCHEMA_NAME        := I_SCHEMA_NAME;
        self.TABLE_NAME         := I_TABLE_NAME;
        self.PRIMARY_KEY_COLUMN := F_PK ( I_TABLE_NAME, I_SCHEMA_NAME );
        self.PRIMARY_KEY_VALUE  := I_PRIMARY_KEY;
        self.DATE_FIELDS        := new T_DATA_FIELD_DATE_LIST   ();
        self.NUMERIC_FIELDS     := new T_DATA_FIELD_NUMERIC_LIST();
        self.STRING_FIELDS      := new T_DATA_FIELD_STRING_LIST ();
        READ_DATA;
        return;
    end;

    -- use the current schema
    constructor function T_DATA_RECORD ( I_TABLE_NAME  in varchar2, 
                                         I_PRIMARY_KEY in varchar2 ) return self as result is
    begin
        self.SCHEMA_NAME        := NVL(UPPER(SUBSTR(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'),1, 40)),'UNKNOWN');
        self.TABLE_NAME         := I_TABLE_NAME;
        self.PRIMARY_KEY_COLUMN := F_PK ( I_TABLE_NAME );
        self.PRIMARY_KEY_VALUE  := I_PRIMARY_KEY;
        self.DATE_FIELDS        := new T_DATA_FIELD_DATE_LIST   ();
        self.NUMERIC_FIELDS     := new T_DATA_FIELD_NUMERIC_LIST();
        self.STRING_FIELDS      := new T_DATA_FIELD_STRING_LIST ();
        READ_DATA;
        return;
    end;

    ---------- 
    -- Methods
    ---------- 

    --------------------------------------------------
    -- read it from the table
    member procedure READ_DATA is
    --------------------------------------------------
        L_SQL         varchar2(32000)  := null;
        L_DATE        date;
        L_STRING      varchar2(32000);
        L_NUMERIC     number;
    begin

        if self.TABLE_NAME is not null then

            if self.PRIMARY_KEY_VALUE is not null and self.PRIMARY_KEY_COLUMN is not null then

                self.LAST_OPERATION := 'S';

            -- DATE
                for L_DR IN ( select COLUMN_NAME 
                                from ALL_TAB_COLUMNS TC 
                               where TC.OWNER       = self.SCHEMA_NAME
                                 and TC.TABLE_NAME  = self.TABLE_NAME
                                 and DATA_TYPE IN ('DATE')
                                 and COLUMN_NAME != self.PRIMARY_KEY_COLUMN
                               order by COLUMN_ID
                            ) 
                loop
                    L_SQL := 'select '||L_DR.COLUMN_NAME||' from '||self.TABLE_NAME||' where '||self.PRIMARY_KEY_COLUMN||'='''||self.PRIMARY_KEY_VALUE||'''';
                    begin
                        execute immediate L_SQL into L_DATE;
                    exception when others then
                        L_DATE := null;
                    end;
                    self.DATE_FIELDS.extend;
                    self.DATE_FIELDS( self.DATE_FIELDS.count ) := new T_DATA_FIELD_DATE( L_DR.COLUMN_NAME, L_DATE );
                end loop;

            -- NUMERIC
                for L_NR IN ( select COLUMN_NAME 
                                from ALL_TAB_COLUMNS TC 
                               where TC.OWNER       = self.SCHEMA_NAME
                                 and TC.TABLE_NAME  = self.TABLE_NAME
                                 and DATA_TYPE IN ('FLOAT','NUMBER')
                                 and COLUMN_NAME != self.PRIMARY_KEY_COLUMN
                               order by COLUMN_ID
                            ) 
                loop
                    L_SQL := 'select '||L_NR.COLUMN_NAME||' from '||self.TABLE_NAME||' where '||self.PRIMARY_KEY_COLUMN||'='''||self.PRIMARY_KEY_VALUE||'''';
                    begin
                        execute immediate L_SQL into L_NUMERIC;
                    exception when others then
                        L_NUMERIC := null;
                    end;
                    self.NUMERIC_FIELDS.extend;
                    self.NUMERIC_FIELDS( self.NUMERIC_FIELDS.count ) := new T_DATA_FIELD_NUMERIC( L_NR.COLUMN_NAME, L_NUMERIC );
                end loop;

            -- STRING
                for L_SR IN ( select COLUMN_NAME 
                                from ALL_TAB_COLUMNS TC 
                               where TC.OWNER       = self.SCHEMA_NAME
                                 and TC.TABLE_NAME  = self.TABLE_NAME
                        and DATA_TYPE IN ('CHAR','NCHAR','NVARCHAR2','VARCHAR2')
                                 and COLUMN_NAME != self.PRIMARY_KEY_COLUMN
                               order by COLUMN_ID
                            ) 
                loop
                    L_SQL := 'select '||L_SR.COLUMN_NAME||' from '||self.TABLE_NAME||' where '||self.PRIMARY_KEY_COLUMN||'='''||self.PRIMARY_KEY_VALUE||'''';
                    begin
                        execute immediate L_SQL into L_STRING;
                    exception when others then
                        L_STRING := null;
                    end;
                    self.STRING_FIELDS.extend;
                    self.STRING_FIELDS( self.STRING_FIELDS.count ) := new T_DATA_FIELD_STRING( L_SR.COLUMN_NAME, L_STRING );
                end loop;

            end if;

        end if;

    end;

    --------------------------------------------------
    -- it will be insert or update
    member procedure WRITE_DATA is
    --------------------------------------------------
        L_CNT           number;
        L_SQL           varchar2( 32000 );
        L_FIELD_LIST    varchar2( 32000 );
        L_VALUE_LIST    varchar2( 32000 );
    begin
        -- insert or update
        execute immediate 'select count(*) from '||self.TABLE_NAME||' where '||self.PRIMARY_KEY_COLUMN||'='''||self.PRIMARY_KEY_VALUE||'''' into L_CNT;
        
        if L_CNT = 0 then
        -- insert

            L_FIELD_LIST := self.PRIMARY_KEY_COLUMN || ',';
            L_VALUE_LIST := ''''||self.PRIMARY_KEY_VALUE || ''',';

            -- DATE
            for L_RN in 1..self.DATE_FIELDS.count loop    
                L_FIELD_LIST := L_FIELD_LIST || self.DATE_FIELDS(L_RN).NAME || ',';
                if self.DATE_FIELDS(L_RN).VALUE is not null then
                    L_VALUE_LIST := L_VALUE_LIST || 'TO_DATE('''|| to_char( self.DATE_FIELDS(L_RN).VALUE,'YYYYMMDDHH24MISS') || ''',''YYYYMMDDHH24MISS''),';
                else
                    L_VALUE_LIST := L_VALUE_LIST || 'null,';
                end if;
            end loop;

            -- NUMERIC
            for L_RN in 1..self.NUMERIC_FIELDS.count loop    
                L_FIELD_LIST := L_FIELD_LIST || self.NUMERIC_FIELDS(L_RN).NAME || ',';
                if self.NUMERIC_FIELDS(L_RN).VALUE is not null then
                    L_VALUE_LIST := L_VALUE_LIST || replace( self.NUMERIC_FIELDS(L_RN).VALUE,',','.') || ',';
                else
                    L_VALUE_LIST := L_VALUE_LIST || 'null,';
                end if;
            end loop;

            -- STRING
            for L_RN in 1..self.STRING_FIELDS.count loop    
                L_FIELD_LIST := L_FIELD_LIST || self.STRING_FIELDS(L_RN).NAME || ',';
                if self.STRING_FIELDS(L_RN).VALUE is not null then
                    L_VALUE_LIST := L_VALUE_LIST || '''' || replace( self.STRING_FIELDS(L_RN).VALUE,'''','''''') || ''',';
                else
                    L_VALUE_LIST := L_VALUE_LIST || 'null,';
                end if;
            end loop;

            if L_FIELD_LIST is not null and L_VALUE_LIST is not null then
                -- trim the last comma
                L_FIELD_LIST := substr( L_FIELD_LIST,1,length(L_FIELD_LIST)-1 );
                L_VALUE_LIST := substr( L_VALUE_LIST,1,length(L_VALUE_LIST)-1 );

                L_SQL := 'insert into '||self.TABLE_NAME|| '(' || L_FIELD_LIST ||') values ('|| L_VALUE_LIST ||')';
                self.LAST_OPERATION := 'I';
                begin
                    execute immediate L_SQL;
                exception when others then
                    self.LAST_ERRCODE := sqlcode;
                    self.LAST_ERRMSG  := sqlerrm;
                end;
            end if;

        else
        -- update

            -- DATE
            for L_RN in 1..self.DATE_FIELDS.count loop    
                if self.DATE_FIELDS(L_RN).VALUE is not null then
                    L_VALUE_LIST := L_VALUE_LIST || self.DATE_FIELDS(L_RN).NAME || '=' ||
                                    'TO_DATE('''|| to_char(self.DATE_FIELDS(L_RN).VALUE,'YYYYMMDDHH24MISS') || ''',''YYYYMMDDHH24MISS''),';
                else
                    L_VALUE_LIST := L_VALUE_LIST || self.DATE_FIELDS(L_RN).NAME || '= null,' ;
                end if;
            end loop;

            -- NUMERIC
            for L_RN in 1..self.NUMERIC_FIELDS.count loop    
                if self.NUMERIC_FIELDS(L_RN).VALUE is not null then
                    L_VALUE_LIST := L_VALUE_LIST || self.NUMERIC_FIELDS(L_RN).NAME || '=' ||
                                    replace(self.NUMERIC_FIELDS(L_RN).VALUE,',','.') || ',';
                else
                    L_VALUE_LIST := L_VALUE_LIST || self.NUMERIC_FIELDS(L_RN).NAME || '= null,' ;
                end if;
            end loop;

            -- STRING
            for L_RN in 1..self.STRING_FIELDS.count loop    
                if self.STRING_FIELDS(L_RN).VALUE is not null then
                    L_VALUE_LIST := L_VALUE_LIST || self.STRING_FIELDS(L_RN).NAME || '=''' ||
                                    replace(self.STRING_FIELDS(L_RN).VALUE,'''','''''') || ''',';
                else
                    L_VALUE_LIST := L_VALUE_LIST || self.STRING_FIELDS(L_RN).NAME || '= null,' ;
                end if;
            end loop;

            if L_VALUE_LIST is not null then
                -- trim the last comma
                L_VALUE_LIST := substr( L_VALUE_LIST,1,length(L_VALUE_LIST)-1 );

                L_SQL := 'update '||self.TABLE_NAME|| ' set ' || L_VALUE_LIST ||' where '||self.PRIMARY_KEY_COLUMN||'='''||self.PRIMARY_KEY_VALUE||'''';
                self.LAST_OPERATION := 'U';
                begin
                    execute immediate L_SQL;
                exception when others then
                    self.LAST_ERRCODE := sqlcode;
                    self.LAST_ERRMSG  := sqlerrm;
                end;
            end if;


        end if;
    end;

    --------------------------------------------------
    -- delete it from the table
    member procedure DELETE_DATA is
    --------------------------------------------------
        L_SQL           varchar2( 32000 );
    begin
        L_SQL := 'delete '||self.TABLE_NAME||' where '||self.PRIMARY_KEY_COLUMN||'='''||self.PRIMARY_KEY_VALUE||'''';
        self.LAST_OPERATION := 'D';
        begin
            execute immediate L_SQL;
        exception when others then
            self.LAST_ERRCODE := sqlcode;
            self.LAST_ERRMSG  := sqlerrm;
        end;
    end;

    --------------------------------------------------
    -- set field value
    member procedure SET_VALUE( I_FIELD_NAME varchar2, I_VALUE date    ) is
    --------------------------------------------------
        L_N         number;    
    begin
        if I_FIELD_NAME is not null then
            L_N := 1;
            loop
                exit when L_N > self.DATE_FIELDS.count or self.DATE_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                L_N := L_N + 1;
            end loop;
            if L_N > self.DATE_FIELDS.count then
                self.DATE_FIELDS.extend;
                self.DATE_FIELDS(self.DATE_FIELDS.count) := new T_DATA_FIELD_DATE( I_FIELD_NAME, I_VALUE );
            else
                self.DATE_FIELDS(L_N).VALUE   := I_VALUE;
            end if;
        end if;
    end;

    --------------------------------------------------
    member procedure SET_VALUE( I_FIELD_NAME varchar2, I_VALUE number  ) is
    --------------------------------------------------
        L_N         number;    
    begin
        if I_FIELD_NAME is not null then
            L_N := 1;
            loop
                exit when L_N > self.NUMERIC_FIELDS.count or self.NUMERIC_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                L_N := L_N + 1;
            end loop;
            if L_N > self.NUMERIC_FIELDS.count then
                self.NUMERIC_FIELDS.extend;
                self.NUMERIC_FIELDS(self.NUMERIC_FIELDS.count) := new T_DATA_FIELD_NUMERIC( I_FIELD_NAME, I_VALUE );
            else
                self.NUMERIC_FIELDS(L_N).VALUE   := I_VALUE;
            end if;
        end if;
    end;

    --------------------------------------------------
    member procedure SET_VALUE( I_FIELD_NAME varchar2, I_VALUE varchar2) is
    --------------------------------------------------
        L_N         number;    
    begin
        if I_FIELD_NAME is not null then
            L_N := 1;
            loop
                exit when L_N > self.STRING_FIELDS.count or self.STRING_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                L_N := L_N + 1;
            end loop;
            if L_N > self.STRING_FIELDS.count then
                self.STRING_FIELDS.extend;
                self.STRING_FIELDS(self.STRING_FIELDS.count) := new T_DATA_FIELD_STRING( I_FIELD_NAME, I_VALUE );
            else
                self.STRING_FIELDS(L_N).VALUE   := I_VALUE;
            end if;
        end if;
    end;

    --------------------------------------------------
    -- set field to null (exists but is null)
    member procedure SET_NULL ( I_FIELD_NAME varchar2 ) is
    --------------------------------------------------
        L_N      number;    
    begin
        L_N := 1;
        loop
            exit when L_N > self.DATE_FIELDS.count or self.DATE_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
            L_N := L_N + 1;
        end loop;
        if L_N > self.DATE_FIELDS.count then -- Not exists
            L_N := 1;
            loop
                exit when L_N > self.NUMERIC_FIELDS.count or self.NUMERIC_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                L_N := L_N + 1;
            end loop;
            if L_N > self.NUMERIC_FIELDS.count then -- Not exists
                L_N := 1;
                loop
                    exit when L_N > self.STRING_FIELDS.count or self.STRING_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                    L_N := L_N + 1;
                end loop;
                if L_N <= self.STRING_FIELDS.count then 
                    self.STRING_FIELDS(L_N).VALUE := null;
                end if;
            else
                self.NUMERIC_FIELDS(L_N).VALUE := null;
            end if;
        else
            self.DATE_FIELDS(L_N).VALUE := null;
        end if;
    end;

    --------------------------------------------------
    -- is null? if the field does not exist return with null !
    member function  IS_NULL  (I_FIELD_NAME varchar2) return boolean is
    --------------------------------------------------
        L_N      number;    
    begin
        L_N := 1;
        loop
            exit when L_N > self.DATE_FIELDS.count or self.DATE_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
            L_N := L_N + 1;
        end loop;
        if L_N > self.DATE_FIELDS.count then -- Not exists
            L_N := 1;
            loop
                exit when L_N > self.NUMERIC_FIELDS.count or self.NUMERIC_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                L_N := L_N + 1;
            end loop;
            if L_N > self.NUMERIC_FIELDS.count then -- Not exists
                L_N := 1;
                loop
                    exit when L_N > self.STRING_FIELDS.count or self.STRING_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                    L_N := L_N + 1;
                end loop;
                if L_N <= self.STRING_FIELDS.count then
                    if self.STRING_FIELDS(L_N).VALUE is null then
                        return true;
                    else
                        return false;
                    end if;
                end if;
            else
                if self.STRING_FIELDS(L_N).VALUE is null then
                    return true;
                else
                    return false;
                end if;
            end if;
        else
            if self.STRING_FIELDS(L_N).VALUE is null then
                return true;
            else
                return false;
            end if;
        end if;
        return true;
    end;

    --------------------------------------------------
    -- does the field exist?
    member function  EXIST    (I_FIELD_NAME varchar2) return boolean is
    --------------------------------------------------
        L_RB     boolean      := false;    
        L_N      number;    
    begin
        L_N := 1;
        loop
            exit when L_N > self.DATE_FIELDS.count or self.DATE_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
            L_N := L_N + 1;
        end loop;
        if L_N > self.DATE_FIELDS.count then -- Not exists
            L_N := 1;
            loop
                exit when L_N > self.NUMERIC_FIELDS.count or self.NUMERIC_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                L_N := L_N + 1;
            end loop;
            if L_N > self.NUMERIC_FIELDS.count then -- Not exists
                L_N := 1;
                loop
                    exit when L_N > self.STRING_FIELDS.count or self.STRING_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                    L_N := L_N + 1;
                end loop;
                if L_N <= self.STRING_FIELDS.count then
                    L_RB := true;
                end if;
            else
                L_RB := true;
            end if;
        else
            L_RB := true;
        end if;
        return L_RB;
    end;

    --------------------------------------------------
    -- remove field from field list
    member procedure REMOVE   (I_FIELD_NAME varchar2) is
    --------------------------------------------------
    begin
        null;
    end;

    --------------------------------------------------
    -- get field value functions:
    member function GET_FIELD_TYPE   (I_FIELD_NAME varchar2) return varchar2 is
    --------------------------------------------------
        L_RS     varchar2(2000)  := null;    
        L_N      number;    
    begin
        L_N := 1;
        loop
            exit when L_N > self.DATE_FIELDS.count or self.DATE_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
            L_N := L_N + 1;
        end loop;
        if L_N > self.DATE_FIELDS.count then -- Not exists
            L_N := 1;
            loop
                exit when L_N > self.NUMERIC_FIELDS.count or self.NUMERIC_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                L_N := L_N + 1;
            end loop;
            if L_N > self.NUMERIC_FIELDS.count then -- Not exists
                L_N := 1;
                loop
                    exit when L_N > self.STRING_FIELDS.count or self.STRING_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
                    L_N := L_N + 1;
                end loop;
                if L_N > self.STRING_FIELDS.count then
                    L_RS := null;
                else
                    L_RS := 'STRING';
                end if;
            else
                L_RS := 'NUMERIC';
            end if;
        else
            L_RS := 'DATE';
        end if;
        return L_RS;
    end;

    --------------------------------------------------
    member function GET_DATE_VALUE   (I_FIELD_NAME varchar2) return date is
    --------------------------------------------------
        L_RS     date;    
        L_N      number;    
    begin
        L_N := 1;
        loop
            exit when L_N > self.DATE_FIELDS.count or self.DATE_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
            L_N := L_N + 1;
        end loop;
        if L_N <= self.DATE_FIELDS.count then
            L_RS := self.DATE_FIELDS(L_N).VALUE;
        end if;
        return L_RS;
    end;

    --------------------------------------------------
    member function GET_NUMERIC_VALUE(I_FIELD_NAME varchar2) return number is
    --------------------------------------------------
        L_RS     number;    
        L_N      number;    
    begin
        L_N := 1;
        loop
            exit when L_N > self.NUMERIC_FIELDS.count or self.NUMERIC_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
            L_N := L_N + 1;
        end loop;
        if L_N <= self.NUMERIC_FIELDS.count then
            L_RS := self.NUMERIC_FIELDS(L_N).VALUE;
        end if;
        return L_RS;
    end;

    --------------------------------------------------
    member function GET_STRING_VALUE (I_FIELD_NAME varchar2) return varchar2 is
    --------------------------------------------------
        L_RS     varchar2(32000);    
        L_N      number;    
    begin
        L_N := 1;
        loop
            exit when L_N > self.STRING_FIELDS.count or self.STRING_FIELDS(L_N).NAME = upper(I_FIELD_NAME); 
            L_N := L_N + 1;
        end loop;
        if L_N <= self.STRING_FIELDS.count then
            L_RS := self.STRING_FIELDS(L_N).VALUE;
        end if;
        return L_RS;
    end;

    --------------------------------------------------
    -- write the record to the dbms_outpt:
    member procedure PRINT ( I_DEBUG_MESSAGE varchar2 default null) is
    --------------------------------------------------
        L_RS     varchar2(32000) := null;    
        L_N      number;    
    begin
        DBMS_OUTPUT.ENABLE( NULL );
        DBMS_OUTPUT.PUT_LINE( ' --- ' || I_DEBUG_MESSAGE ||  ' ---------------' );

        for L_RN in 1..self.NUMERIC_FIELDS.count loop
            DBMS_OUTPUT.PUT_LINE( self.NUMERIC_FIELDS(L_RN).NAME || ': ' || self.NUMERIC_FIELDS(L_RN).VALUE );
        end loop; 

        for L_RN in 1..self.STRING_FIELDS.count loop
            DBMS_OUTPUT.PUT_LINE( self.STRING_FIELDS(L_RN).NAME || ': ' || self.STRING_FIELDS(L_RN).VALUE );
        end loop; 

        for L_RN in 1..self.DATE_FIELDS.count loop
            DBMS_OUTPUT.PUT_LINE( self.DATE_FIELDS(L_RN).NAME || ': ' || self.DATE_FIELDS(L_RN).VALUE );
        end loop; 
      
        DBMS_OUTPUT.PUT_LINE( '^^^ end of data ^^^^^' );
    end;


end;
/


