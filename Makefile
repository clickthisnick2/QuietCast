# QuietCast checks. CI runs `make check` and nothing else.
SWIFT ?= swift
COVERAGE_FLOOR ?= 98
SIZE_BUDGET ?= 186617

.PHONY: check lint test coverage format spelling workflows size

check: lint test coverage

lint: format spelling workflows size

test:
	$(SWIFT) test --enable-code-coverage

coverage:
	sh scripts/coverage_floor.sh $(COVERAGE_FLOOR)

format:
	$(SWIFT) format lint --recursive --strict --configuration .swift-format QuietCast QuietCastTests Package.swift

spelling:
	codespell

workflows:
	actionlint

size:
	sh scripts/size_budget.sh $(SIZE_BUDGET)
