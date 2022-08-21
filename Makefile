EXTENSION = pg_query_tool
MODULES = pg_query_tool
DATA = pg_query_tool--1.0.sql
REGRESS = pg_query_tool

PG_CPPFLAGS = -g -O2

ifndef PG_CONFIG
	PG_CONFIG := pg_config
endif
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
