Fyler
=====

Fyler is a distributed Erlang application for handling different file processing tasks.

_Server_ application behaves as queue master, load balancer and API entry point.

_Pool_ applications are just pools of workers. Pools can be divided by categories. 

All _handlers_ are just wrappers for system calls.

Usual task lifecycle
--------------------

1. Send task to Server as POST request (with path to file and task type as mandatory fields).

2. Server verifies task and queues it.

3. Server sends task to Pool.

4. Pool downloads file. Currently only download from AWS S3 is supported.

5. Pool starts worker.

6. Worker finishes task (successfully or not) and notify Pool and Server. If task was finished successfully and worker uploads resulting files to S3.

7. Server handle task event and send HTTP POST request with results if callback was provided.


System Dependencies
-------------
0. Erlang >=17. 

1. Postgres database.
Use scripts/setup_db.erl script to create scheme.

2. AWS CLI (for using with AWS S3 storage).

3. Handlers' dependant tools (e.g. ffmpeg, gs, unoconv, swftools, pdftk, imagemagick, etc.).

Configuration
-------------

Fyler's configuration can be stored in app.config or in fyler app priv dir or in '/etc' as "fyler.config".

```{role, server|pool}.``` - defines the role of the node
%% pool params
```{server_name, fyler@domain.com}.``` - server node name for pool nodes
```{category, video|document|...}.``` - category of tasks pool can handle
```{storage_dir,"ff/"}.``` - where to place temp files
```{max_active,1}.``` - number of maximum concurrent workers


%% server params
```{http_port,8008}.```

```{aws_s3_bucket, ["tbconvert"]}.``` - List of supported AWS S3 buckets
```{aws_dir,"ff/"}.``` - AWS S3 prefix to upload

```{auth_login,"fad"}.```  - login for API access
```{auth_pass,"<passwordhash>"}.``` - password hash for API access (for now simply `md5(plain_pass)`)

%%% db settings
```{pg_host,"127.0.0.1"}.
   {pg_db,"fyler"}.
   {pg_user,"fyler"}.
   {pg_pass,"fyler"}.
   {pg_pool_size, 5}.
   {pg_max_overflow, 10}. ```  - Postgres and poolboy config.


Vagrant+ansible
-------------
[Here](https://github.com/palkan/fyler-vm).

#### AWS

To work with AWS you must have AWS CLI installed and configured for Fyler's user.

All AWS operation are performed using commands like ```aws s3 sync <1> <2>```.

#### TODO
* tasks priority 
* acl support for API
* autostart new instance when all pools are busy
* ...