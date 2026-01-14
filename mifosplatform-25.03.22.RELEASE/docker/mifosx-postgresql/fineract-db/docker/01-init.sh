#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements. See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership. The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.
#

set -e
export PGPASSWORD=$POSTGRES_PASSWORD;

# Create databases (use IF NOT EXISTS to be idempotent)
psql -v ON_ERROR_STOP=0 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  -- Create user if not exists (ignore error if already exists)
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$FINERACT_DB_USER') THEN
      CREATE USER $FINERACT_DB_USER WITH PASSWORD '$FINERACT_DB_PASS';
    END IF;
  END
  \$\$;
EOSQL

# Create databases
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  SELECT 'CREATE DATABASE $FINERACT_TENANTS_DB_NAME'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$FINERACT_TENANTS_DB_NAME')\gexec

  SELECT 'CREATE DATABASE $FINERACT_TENANT_DEFAULT_DB_NAME'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$FINERACT_TENANT_DEFAULT_DB_NAME')\gexec
EOSQL

# Grant privileges
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  GRANT ALL PRIVILEGES ON DATABASE $FINERACT_TENANTS_DB_NAME TO $FINERACT_DB_USER;
  GRANT ALL PRIVILEGES ON DATABASE $FINERACT_TENANT_DEFAULT_DB_NAME TO $FINERACT_DB_USER;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$FINERACT_TENANTS_DB_NAME" <<-EOSQL
  GRANT ALL ON SCHEMA public TO $FINERACT_DB_USER;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$FINERACT_TENANT_DEFAULT_DB_NAME" <<-EOSQL
  GRANT ALL ON SCHEMA public TO $FINERACT_DB_USER;
EOSQL

echo "Fineract databases initialized successfully"