Fyler
=====

Fyler is a distributed Erlang application for handling different file processing tasks.

_Server_ application behaves as queue master, load balancer and API entry point.

_Pool_ applications are just pools of workers.

All handlers are just wrappers for system calls.

Usual task lifecycle
--------------------

1. Send task to Server as POST request (with path to file and task type as mandatory fields).

2. Server verifies task and queues it.

3. Server sends task to Pool.

4. Pool downloads file. Currently supported two possible variants: download from AWS S3, or download over HTTP.

5. Pool starts worker.

6. Worker finishes task (successfully or not) and notify Pool and Server. If task was finished successfully and AWS S3 is available
worker uploads resulting files to S3.

7. Server handle task event and send HTTP POST request with results if callback was provided.


System Dependencies
-------------

1. Postgres database.
Use scripts/setup_db.erl script to create scheme.

2. AWS CLI (for using with AWS S3 storage).

3. Handlers' dependant tools (e.g. ffmpeg, gs, unoconv, swftools, jpegtran, imagemagick, etc.).

Configuration
-------------

Erlang app.config contains only configuration for lager and cowboy.

Fyler's own configuration is stored in fyler app priv dir as "fyler.config".

```{role, server|pool}.``` - defines the role of the node
```{server_name, fyler@domain.com}.``` - server node name for pool nodes
```{storage_dir,"ff/"}.``` - where to place temp files
```{http_port,8008}.```

```{auth_login,"fad"}.```  - login for API access
```{auth_pass,"<passwordhash>"}.``` - password hash for API access.

```{aws_s3_bucket, "tbconvert"}.``` - AWS S3 bucket name
```{aws_dir,"ff/"}.``` - AWS S3 prefix to upload

```{pg_host,"127.0.0.1"}.
   {pg_db,"fyler"}.
   {pg_user,"fyler"}.
   {pg_pass,"fyler"}.
   {pg_pool_size, 5}.
   {pg_max_overflow, 10}. ```  - Postgres and poolboy config.


#### AWS

Using AWS S3 bucket for target files is recommended when Fyler's pools are AWS too.
To work with AWS you must have AWS CLI installed and configured for Fyler's user.

All AWS operation are performed using commands like ```aws s3 sync <1> <2>```.

**Note**: Uploaded files are all public for now (because uploading use option ```--acl public-read```).


#### Handlers

Use scripts/gen_handlers_list.erl to generate .hrl file with list of available handlers used in fyler_pool.erl.
