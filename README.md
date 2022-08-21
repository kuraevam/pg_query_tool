# pg_query_tool
Query tool for PostgreSQL

```
val_varchar_of_json(data, filed);
val_bool_of_json(data, filed);
val_float8_of_json(data, filed);
val_int2_of_json(data, filed);
val_int4_of_json(data, filed);
val_int8_of_json(data, filed);
val_json_of_json(data, filed);
val_polygon_of_json(data, filed);
val_text_of_json(data, filed);
val_varchar_of_json(data, filed);
val_varchar_of_json(data, filed);

q_build
q_exclude_basic_fields
q_exec_json
q_field
q_group_by
q_inner_join
q_limit
q_offset
q_order_by
q_table
q_table_alias
q_table_name
q_table_schema
q_where
```

### Example
```
CREATE FUNCTION control_panel.get_user_list(arg_data json) RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE

dec_page integer;
dec_items_per_page integer;
dec_query json;
dec_server_items_length bigint;
dec_query_result json;
begin
	
	dec_page = pglib.val_int4_of_json(arg_data, '{option_table, page}', 1);
	dec_items_per_page = pglib.val_int4_of_json(arg_data, '{option_table, items_per_page}', 5);	
	
	-- server_items_length
	dec_query = null;
	dec_query = pglib.q_exclude_basic_fields(dec_query);
	dec_query = pglib.q_field(dec_query, 'count(id) as "row_count"');
	dec_server_items_length = pglib.val_int4_of_json(
														pglib.q_exec_json
														(
															control_panel.q_users(dec_query),
															false
														), 
														'row_count'
													);
	
	-- option_table										
	dec_query = null;
	dec_query = pglib.q_field(dec_query, format('%s as "page"', dec_page));
	dec_query = pglib.q_field(dec_query, format('%s as "items_per_page"', dec_items_per_page));
	dec_query = pglib.q_field(dec_query, format('%s as "server_items_length"', dec_server_items_length));
	
	dec_query_result = pglib.q_field(dec_query_result, format('(%s)[1] as "option_table"', pglib.q_table(dec_query)));
						

	-- items
	dec_query = null;
	dec_query = pglib.q_field(dec_query, 'hash_password', true);
	dec_query = pglib.q_order_by(dec_query, 'date_created');	
	dec_query = pglib.q_limit(dec_query, dec_items_per_page::varchar);
	dec_query = pglib.q_offset(dec_query, (dec_items_per_page * (dec_page - 1))::varchar);
	
	dec_query_result = pglib.q_field(dec_query_result,format('%s as "items"', control_panel.q_users(dec_query)));

	
   	RETURN pglib.q_exec_json(
   							pglib.q_table(dec_query_result), 
   							false
   						);
END;
$$;

CREATE FUNCTION control_panel.q_users(arg_data json) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN   
	 
	arg_data = pglib.q_table_schema(arg_data, 'public');
	arg_data = pglib.q_table_name(arg_data, 'users');
	arg_data = pglib.q_table_alias(arg_data, 'p_user');
	
	RETURN  pglib.q_build(arg_data);
END;
$$;
```
