TF ?= terraform
PYTHON ?= python3

.PHONY: check init fmt validate test bootstrap security
check:
	$(MAKE) init
	$(MAKE) fmt validate test bootstrap

init:
	$(TF) init -backend=false -input=false

fmt:
	$(TF) fmt -check -recursive

validate:
	$(TF) validate -no-color

test:
	$(TF) test -no-color

bootstrap:
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py'

security:
	trivy config --skip-check-update --severity HIGH,CRITICAL --exit-code 1 .
