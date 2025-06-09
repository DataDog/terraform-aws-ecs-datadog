fmt:
	terraform fmt -recursive .
license:
	dd-license-attribution https://github.com/datadog/terraform-aws-ecs-datadog/ --no-gh-auth > LICENSE-3rdparty.csv
test:
	go test ./tests
