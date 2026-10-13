MODULES := network aks postgres monitoring meter-platform
ENVS    := dev uat staging prod
TF      ?= terraform

.PHONY: fmt fmt-check validate test lint check

fmt:
	$(TF) fmt -recursive

fmt-check:
	$(TF) fmt -recursive -check -diff

# Validate every module and environment without a backend or credentials.
validate:
	@for m in $(MODULES); do \
		echo "== module $$m"; \
		(cd modules/$$m && $(TF) init -backend=false -input=false >/dev/null && $(TF) validate) || exit 1; \
	done
	@for e in $(ENVS); do \
		echo "== env $$e"; \
		(cd envs/$$e && $(TF) init -backend=false -input=false >/dev/null && $(TF) validate) || exit 1; \
	done

# Offline tests with mock providers. No Azure account needed.
test:
	@for m in network aks postgres meter-platform; do \
		echo "== testing $$m"; \
		(cd modules/$$m && $(TF) init -backend=false -input=false >/dev/null && $(TF) test) || exit 1; \
	done

lint:
	tflint --init --config "$(CURDIR)/.tflint.hcl"
	tflint --recursive --config "$(CURDIR)/.tflint.hcl"

check: fmt-check validate test
