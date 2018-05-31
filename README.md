# Demo of scheduling jobs with Docker on Pivotal Web Services and Pivotal Cloud Foundry

This is a follow on from an article we wrote about [using PCF/PWS to schedule jobs](https://starkandwayne.com/blog/schedule-containers-in-pivotal-cloud-foundry/). In this project we schedule a job to fetch the daily Dilbert cartoon and store it in an AWS S3 bucket for safe keeping. It will be a lot easier to do this with a Docker image than a Cloud Foundry buildpack.

We'll use the following tools:

* [`curl`](https://curl.haxx.se/) to fetch the latest https://dilbert.com HTML and the daily image
* [`pup`](https://github.com/ericchiang/pup) to parse the HTML and discover the daily image URL
* [`aws-cli`](https://aws.amazon.com/cli/) to upload the image to our s3 bucket

See the `Dockerfile` for their installation into an [Alpine](https://alpinelinux.org/) base image.

## Build & test Docker image

```plain
docker build -t starkandwayne/pcf-docker-scheduler-demo .
docker run -e S3_BUCKET=pcf-docker-scheduler-demo \
    -e AWS_ACCESS_KEY_ID=... -e AWS_SECRET_ACCESS_KEY=... \
    starkandwayne/pcf-docker-scheduler-demo
```

In order for PWS/PCF to be able to use the Docker image we need to push the local image to a Docker registry (for example, free [Docker Hub](https://hub.docker.com/r/starkandwayne/pcf-docker-scheduler-demo/) or on-premise, open-source [Harbor](https://github.com/vmware/harbor)):

```plain
docker push starkandwayne/pcf-docker-scheduler-demo
```

## Deploy and schedule daily job

The steps for deploying and scheduling a task using PWS/PCF Scheduler service are the same as [our previous article](https://starkandwayne.com/blog/schedule-containers-in-pivotal-cloud-foundry/).

The differences are in the `cf push` command or `manifest.yml` attributes. See the CF docs on [Deploy an App with Docker](https://docs.cloudfoundry.org/devguide/deploy-apps/push-docker.html).

We are not running a long-running Docker container, so we do not need to listen to ports, but we do need to check that `cf push` staging works. Specifically, that our Cloud Foundry can access our Docker Registry to fetch the image, and that we're passing all the environment variables.

Our `run.sh` script requires three environment variables: `S3_BUCKET`, `AWS_ACCESS_KEY_ID`, and `AWS_SECRET_ACCESS_KEY`.

Let's trying `cf push` without providing them:

```plain
cf push -f manifest-no-env-vars.yml
```

This will fail with the error and suggestion:

```plain
Start unsuccessful

TIP: use 'cf logs pcf-docker-scheduler-demo --recent' for more information
```

Looking at the logs we see errors from our missing env vars:

```plain
   2018-06-01T09:32:27.59+1000 [APP/PROC/WEB/0] ERR /run.sh: line 6: S3_BUCKET: required
   2018-06-01T09:32:27.62+1000 [APP/PROC/WEB/0] OUT Exit status 1
```

This project provides a working `manifest.yml` that specifies the three required environment variables, but you must provide them yourself via `cf push`:


```yaml
applications:
- name: pcf-docker-scheduler-demo
  ...
  docker:
    image: starkandwayne/pcf-docker-scheduler-demo
  env:
    S3_BUCKET: ((S3_BUCKET))
    AWS_ACCESS_KEY_ID: ((AWS_ACCESS_KEY_ID))
    AWS_SECRET_ACCESS_KEY: ((AWS_SECRET_ACCESS_KEY))
```

If we `cf push` this manifest we get fast errors for missing variables (added to [`cf` v6.37.0](https://github.com/cloudfoundry/cli/releases/tag/v6.37.0)):

```plain
$ cf --version
cf version 6.37.0+a40009753.2018-05-25
$ cf push
Pushing from manifest to org starkandwayne / space bom-charts as drnic@starkandwayne.com...
Using manifest file /Users/drnic/Projects/starkandwayne/demos/pcf-docker-scheduler-demo/manifest.yml
Expected to find variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, S3_BUCKET
FAILED
```

Either use `--var` to pass in each variable (e.g. `cf push --var S3_BUCKET=pcf-docker-scheduler-demo ...`) or put the variables in a local file and pass in with `--vars-file` flag:

```plain
cf push --var S3_BUCKET=pcf-docker-scheduler-demo \
    --var AWS_ACCESS_KEY_ID=... \
    --var AWS_SECRET_ACCESS_KEY=...
```

This time, `cf push` will "work" but it still looks like its failing (because we're running a short script not a long-running command):

```plain
$ cf logs pcf-docker-scheduler-demo --recent
...
   2018-06-01T09:41:39.63+1000 [APP/PROC/WEB/0] OUT Testing AWS credentials to access s3://pcf-docker-scheduler-demo
   2018-06-01T09:41:40.29+1000 [APP/PROC/WEB/0] OUT                            PRE dilbert/
   2018-06-01T09:41:40.74+1000 [APP/PROC/WEB/0] OUT Found image for 2018-05-31
   2018-06-01T09:41:40.87+1000 [APP/PROC/WEB/0] OUT Uploading to s3://pcf-docker-scheduler-demo
   2018-06-01T09:41:41.53+1000 [APP/PROC/WEB/0] OUT Completed 130.9 KiB/130.9 KiB (1.3 MiB/s) with 1 file(s) remaining
   2018-06-01T09:41:41.53+1000 [APP/PROC/WEB/0] OUT upload: ./2018-05-31.png to s3://pcf-docker-scheduler-demo/dilbert/2018-05-31.png
   2018-06-01T09:41:41.58+1000 [APP/PROC/WEB/0] OUT Exit status 0
```

These logs look good. Our `run.sh` script exits with status 0. We can now stop our application container (its currently repeatedly fetching the latest comic and uploading to S3).

```plain
cf stop pcf-docker-scheduler-demo
```

And finally, we can setup PWS/PCF Scheduler to run our container once per day:

```plain
cf create-service scheduler-for-pcf standard pcf-docker-scheduler-demo
cf bind-service pcf-docker-scheduler-demo pcf-docker-scheduler-demo

cf create-job pcf-docker-scheduler-demo fetch-daily-dilbert "./run.sh"
cf schedule-job fetch-daily-dilbert "0 1 ? * *"
```

Give the job a test-run:

```plain
cf run-job fetch-daily-dilbert
```

This will schedule our container task to run at UTC 1am each day.

Confirm the initial job run is successful:

```plain
cf job-history fetch-daily-dilbert
```
