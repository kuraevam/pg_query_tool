-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pg_query_tool" to load this file. \quit

CREATE TYPE pg_query_tool;

CREATE FUNCTION _date_to_ms(arg_date timestamp without time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
 RETURN  (date_part('epoch'::text, arg_date) * (1000)::double precision);
END;
$$;

CREATE FUNCTION _date_to_ms(arg_date timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
 RETURN  (date_part('epoch'::text, arg_date) * (1000)::double precision);
END;
$$;


CREATE FUNCTION _has_value(arg_data character varying) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
begin
	/*
	 * Проверять на пустое значение в переменной
	 */
    if arg_data is not null and (length(trim(arg_data)) = 0 or trim(arg_data) = '[]') then
        arg_data = null;
    end if;

    RETURN arg_data;
END;
$$;

CREATE FUNCTION _q_condition(arg_data json, arg_condition_cmd character varying, arg_condition character varying, arg_is_data_array boolean) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
dec_array varchar[];
BEGIN
    /*
     * Конструктор параметров запроса
     */
    if arg_data is null then
        arg_data = '{}';
    end if;

   	if arg_is_data_array then
   		dec_array = ARRAY(select tt::varchar from json_array_elements_text(arg_data->arg_condition_cmd) as tt) || arg_condition;

    	RETURN  arg_data::jsonb || jsonb_build_object(arg_condition_cmd, dec_array);
   	else
   		RETURN arg_data::jsonb || jsonb_build_object(arg_condition_cmd, arg_condition);
   	end if;



END;
$$;

CREATE FUNCTION json(arg_data json, arg_condition_cmd character varying, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    /*
     * Конструктор параметров запроса
     */
    if arg_data is null then
        arg_data = '{}';
    end if;

   	RETURN arg_data::jsonb || jsonb_build_object(arg_condition_cmd, arg_condition);
END;
$$;

CREATE FUNCTION ms_to_timestamp(arg_ms double precision) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
 RETURN to_timestamp(arg_ms/ 1000);
END;
$$;

CREATE FUNCTION now() RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
 RETURN  _date_to_ms(now()::timestamp without time zone);
END;
$$;

CREATE FUNCTION q_build(arg_data json) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
dec_table varchar;
dec_inner_join varchar;
dec_where varchar;
dec_order_by VARCHAR;
dec_group_by VARCHAR;
dec_limit varchar;
dec_offset varchar;
dec_fields varchar;
dec_item varchar;
dec_query varchar;
dec_table_schema varchar;
dec_table_name varchar;
dec_table_alias varchar;
dec_exclude_fields varchar[];
dec_column_name varchar;
dec_include_fields varchar[];
dec_field_array varchar[];
dec_is_exclude_basic_fields bool;
begin
	/*
	 * Формирование запросa
	 */


	dec_table_name = arg_data->>'table_name';
	dec_is_exclude_basic_fields = coalesce(cast(arg_data->>'is_exclude_basic_fields' as bool), false);

	if dec_table_name is not null then
		dec_table_schema = coalesce(arg_data->>'table_schema', '');
		dec_table_alias = coalesce(arg_data->>'table_alias', '');

		if trim(dec_table_schema) = '' then
			raise exception 'not_specified_table_schema';
		end if;

		if trim(dec_table_name) = '' then
			raise exception 'not_specified_table_name';
		end if;

		if trim(dec_table_alias) = '' then
			raise exception 'not_specified_table_alias';
		end if;

		if not dec_is_exclude_basic_fields then
			dec_exclude_fields = ARRAY(select elm::varchar from json_array_elements_text(arg_data->'exclude_fields') as elm);
			FOR dec_column_name in SELECT column_name FROM information_schema.columns
				WHERE 	table_schema = dec_table_schema and
					table_name = dec_table_name
		  	loop
		  		-- EXCLUDE FIELD
		  		if dec_exclude_fields @> array[dec_column_name] then
		    		continue;
		    	end if;

		    	dec_field_array = dec_field_array || format('%s.%s', dec_table_alias, dec_column_name)::varchar;
		   	END LOOP;
		end if;

	   	dec_table = format('%s.%s as %s', dec_table_schema, dec_table_name, dec_table_alias);
	   	dec_table = format('FROM %s', dec_table);

	end if;

   	-- INCLUDE FIELD
   	dec_include_fields = ARRAY(select elm::varchar from json_array_elements_text(arg_data->'include_fields') as elm);
   	dec_field_array = dec_field_array || dec_include_fields;
   	dec_fields = array_to_string(dec_field_array, ',');

    -- INNER JOIN
   	dec_inner_join = array_to_string(array(select elm::varchar from json_array_elements_text(arg_data->'inner_join') as elm),' INNER JOIN ');
   	if dec_inner_join <> '' then
   		dec_inner_join = 'INNER JOIN ' || dec_inner_join;
   	end if;

    -- WHERE
   	dec_where = array_to_string(array(select elm::varchar from json_array_elements_text(arg_data->'where') as elm),') and (');
   	if dec_where <> '' then
   		dec_where = 'where (' || dec_where || ')';
   	end if;

   -- GROUP BY
   	dec_group_by = array_to_string(array(select elm::varchar from json_array_elements_text(arg_data->'group_by') as elm),',');
   	if dec_group_by <> '' then
   		dec_group_by = 'group by ' || dec_group_by;
   	end if;

  	-- ORDER BY
   	dec_order_by = array_to_string(array(select elm::varchar from json_array_elements_text(arg_data->'order_by') as elm),',');
   	if dec_order_by <> '' then
   		dec_order_by = 'order by ' || dec_order_by;
   	end if;

   	-- LIMIT
   	dec_limit = coalesce(arg_data->>'limit','');
   	if trim(dec_limit) <> '' then
   		dec_limit = 'limit ' || dec_limit ;
   	end if;

   	-- OFFSET
   	dec_offset = coalesce(arg_data->>'offset','');
   	if trim(dec_offset) <> '' then
   		dec_offset = 'offset ' || dec_offset ;
   	end if;

    -- QUERY
    dec_query = format('(SELECT ARRAY (SELECT row_to_json(T) FROM (SELECT %s %s %s %s %s %s %s %s) T))', dec_fields, dec_table, COALESCE(dec_inner_join, ''), COALESCE(dec_where, ''), coalesce (dec_group_by, ''), COALESCE(dec_order_by, ''), dec_limit, dec_offset);

   	--dec_query = replace(dec_query, E'\t', ' ');
   	--dec_query = replace(dec_query, E'\n', '');

    --dec_query = REGEXP_REPLACE(dec_query, '( ){2,}', ' ','ig');
   	--dec_query = REGEXP_REPLACE(dec_query, '( ){2,}', ' ','ig');
   	--raise exception '%',dec_query;
    RETURN  dec_query;
END;
$$;


CREATE FUNCTION q_exclude_basic_fields(arg_data json) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	RETURN  _q_condition(arg_data, 'is_exclude_basic_fields', true::varchar, false);
END;
$$;

CREATE FUNCTION q_exec_json(arg_data character varying, arg_is_array boolean) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
dec_res varchar[] ;
dec_data varchar;
begin
	/*
	 * Выполнить запрос
	 */

    EXECUTE arg_data into dec_res;


   	if not dec_res = '{}' then
   		dec_data = array_to_string(dec_res,',');
   	end if;



   	if arg_is_array then

   		if dec_data is null then
   			dec_data = '[]';
   		else
   			dec_data = '[' || dec_data || ']';
   		end if;
    end if;

   	return dec_data::json;
END;
$$;

CREATE FUNCTION q_field(arg_data json, arg_condition character varying, arg_is_exclude boolean DEFAULT false) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	/*
	 * Добавлять поля на вывод
	 */
	if arg_is_exclude then
		RETURN  _q_condition(arg_data, 'exclude_fields', arg_condition, true);
	else
    	RETURN  _q_condition(arg_data, 'include_fields', arg_condition, true);
   	end if;

END;
$$;

CREATE FUNCTION q_group_by(arg_data json, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	/*
	 * Сортировка данных
	 */
    RETURN  _q_condition(arg_data, 'group_by', arg_condition, true);
END;
$$;

CREATE FUNCTION q_inner_join(arg_data json, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	/*
	 * Объеденять запросы
	 */
    RETURN  _q_condition(arg_data, 'inner_join', arg_condition, true);
END;
$$;

CREATE FUNCTION q_limit(arg_data json, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	/*
	 * Ограничение списка
	 */
    RETURN  _q_condition(arg_data, 'limit', arg_condition, false);
END;
$$;

CREATE FUNCTION q_offset(arg_data json, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	/*
	 * Ограничение списка
	 */
    RETURN  _q_condition(arg_data, 'offset', arg_condition, false);
END;
$$;

CREATE FUNCTION q_ok() RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
 RETURN '{ "result": "ok"}'::json;
END;
$$;

CREATE FUNCTION q_order_by(arg_data json, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	/*
	 * Сортировка данных
	 */
    RETURN  _q_condition(arg_data, 'order_by', arg_condition, true);
END;
$$;

CREATE FUNCTION q_table(arg_data json) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	RETURN  q_build(arg_data);
END;
$$;

CREATE FUNCTION q_table_alias(arg_data json, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
begin

	if arg_data->'table_alias' is null then
   		arg_data = _q_condition(arg_data, 'table_alias', arg_condition, false);
   	end if;
   	return arg_data;
END;
$$;

CREATE FUNCTION q_table_name(arg_data json, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
   	RETURN  _q_condition(arg_data, 'table_name', arg_condition, false);
END;
$$;

CREATE FUNCTION q_table_schema(arg_data json, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
   	RETURN  _q_condition(arg_data, 'table_schema', arg_condition, false);
END;
$$;

CREATE FUNCTION q_where(arg_data json, arg_condition character varying) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	/*
	 * Добавлять условии выборки
	 */
    RETURN  _q_condition(arg_data, 'where', arg_condition, true);
END;
$$;

CREATE FUNCTION val_bool_of_json(arg_data json, arg_key character varying, arg_value boolean DEFAULT NULL::boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $_$
DECLARE
dec_value boolean;
BEGIN
    if arg_key ~* '^\{' and arg_key ~* '\}$' then
    	dec_value = cast(_has_value(arg_data#>>arg_key::varchar[]) as boolean);
    else
        dec_value = cast(_has_value(arg_data->>arg_key) as boolean);
    end if;

     if dec_value is null and arg_value is not null then
        dec_value = arg_value;
    end if;

    RETURN dec_value;
END;
$_$;

CREATE FUNCTION val_float8_of_json(arg_data json, arg_key character varying, arg_value double precision DEFAULT NULL::double precision) RETURNS double precision
    LANGUAGE plpgsql
    AS $_$
DECLARE
dec_value Double Precision;
BEGIN
    if arg_key ~* '^\{' and arg_key ~* '\}$' then
    	dec_value = cast(_has_value(arg_data#>>arg_key::varchar[]) as Double Precision);
    else
        dec_value = cast(_has_value(arg_data->>arg_key) as Double Precision);
    end if;

    if dec_value is null and arg_value is not null then
        dec_value = arg_value;
    end if;

    RETURN dec_value;
END;
$_$;

CREATE FUNCTION val_int2_of_json(arg_data json, arg_key character varying, arg_value smallint DEFAULT NULL::smallint) RETURNS bigint
    LANGUAGE plpgsql
    AS $_$
DECLARE
dec_value bigint;
BEGIN
    if arg_key ~* '^\{' and arg_key ~* '\}$' then
    	dec_value = cast(_has_value(arg_data#>>arg_key::varchar[]) as SMALLINT);
    else
        dec_value = cast(_has_value(arg_data->>arg_key) as SMALLINT);
    end if;

    if dec_value is null and arg_value is not null then
        dec_value = arg_value;
    end if;

    RETURN dec_value;
END;
$_$;

CREATE FUNCTION val_int4_of_json(arg_data json, arg_key character varying, arg_value integer DEFAULT NULL::integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
dec_value integer;
BEGIN
    if arg_key ~* '^\{' and arg_key ~* '\}$' then
    	dec_value = cast(_has_value(arg_data#>>arg_key::varchar[]) as integer);
    else
        dec_value = cast(_has_value(arg_data->>arg_key) as integer);
    end if;

    if dec_value is null and arg_value is not null then
        dec_value = arg_value;
    end if;

    RETURN dec_value;
END;
$_$;

CREATE FUNCTION val_int8_of_json(arg_data json, arg_key character varying, arg_value bigint DEFAULT NULL::bigint) RETURNS bigint
    LANGUAGE plpgsql
    AS $_$
DECLARE
dec_value bigint;
BEGIN
    if arg_key ~* '^\{' and arg_key ~* '\}$' then
    	dec_value = cast(_has_value(arg_data#>>arg_key::varchar[]) as bigint);
    else
        dec_value = cast(_has_value(arg_data->>arg_key) as bigint);
    end if;

    if dec_value is null and arg_value is not null then
        dec_value = arg_value;
    end if;

    RETURN dec_value;
END;
$_$;

CREATE FUNCTION val_json_of_json(arg_data json, arg_key character varying, arg_value json DEFAULT NULL::json) RETURNS json
    LANGUAGE plpgsql
    AS $_$
DECLARE
dec_value json;
BEGIN
    if arg_key ~* '^\{' and arg_key ~* '\}$' then
    	dec_value = (arg_data#>>arg_key::varchar[])::json;
    else
        dec_value = (arg_data->arg_key)::json;
    end if;

    if dec_value is null and arg_value is not null then
        dec_value = arg_value;
    end if;

    RETURN dec_value;
END;
$_$;

CREATE FUNCTION val_polygon_of_json(arg_data json, arg_key character varying, arg_value polygon DEFAULT NULL::polygon) RETURNS polygon
    LANGUAGE plpgsql
    AS $_$
DECLARE
dec_value polygon;
BEGIN
    if arg_key ~* '^\{' and arg_key ~* '\}$' then
    	dec_value = cast(_has_value(arg_data#>>arg_key::varchar[]) as polygon);
    else
        dec_value = cast(_has_value(arg_data->>arg_key) as polygon);
    end if;

    if dec_value is null and arg_value is not null then
        dec_value = arg_value;
    end if;

    RETURN dec_value;
END;
$_$;

CREATE FUNCTION val_text_of_json(arg_data json, arg_key character varying, arg_value text DEFAULT NULL::text) RETURNS text
    LANGUAGE plpgsql
    AS $_$
DECLARE
dec_value Text;
BEGIN
    if arg_key ~* '^\{' and arg_key ~* '\}$' then
    	dec_value = _has_value(arg_data#>>arg_key::varchar[]);
    else
        dec_value = _has_value(arg_data->>arg_key);
    end if;

    if dec_value is null and arg_value is not null then
        dec_value = arg_value;
    end if;

    RETURN dec_value;
END;
$_$;

CREATE FUNCTION val_varchar_of_json(arg_data json, arg_key character varying, arg_value character varying DEFAULT NULL::character varying) RETURNS character varying
    LANGUAGE plpgsql
    AS $_$
DECLARE
dec_value varchar;
dec_keys varchar[];
BEGIN
    if arg_key ~* '^\{' and arg_key ~* '\}$' then
    	dec_value = _has_value(arg_data#>>arg_key::varchar[]);
    else
        dec_value = _has_value(arg_data->>arg_key);
    end if;

    if dec_value is null and arg_value is not null then
        dec_value = arg_value;
    end if;

    RETURN dec_value;
END;
$_$;

