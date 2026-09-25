fmt:
	terraform fmt -recursive .
license:
	dd-license-attribution https://github.com/datadog/terraform-aws-ecs-datadog/ --no-gh-auth > LICENSE-3rdparty.csv
test:
	go test ./tests
test-plan:
	cd modules/ecs_fargate && terraform init -backend=false -input=false && terraform test
pre-commit:
	pre-commit run --all-files
docs:
	@for dir in modules/*/; do \
			echo "Generating docs for $$dir"; \
			(cd $$dir && terraform-docs . --config ../../.terraform-docs.yml); \
	done
