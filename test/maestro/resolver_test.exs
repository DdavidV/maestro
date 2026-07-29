defmodule Maestro.ResolverTest do
  use ExUnit.Case, async: false

  import Maestro.WorkspaceFixtures
  alias Maestro.Resources.Resolver

  setup do
    :ok = isolate_workspace_registry!()
    %{workspace: workspace_fixture()}
  end

  test "resolve suite reference with steps only", %{workspace: workspace} do
    suite = %{
      "id" => "my-suite",
      "testcases" => [
        %{
          "id" => "testcase-1",
          "name" => "testcase 1",
          "steps" => [
            %{
              "client" => "http",
              "template" => "my_template",
              "dataset" => "my_dataset"
            }
          ]
        }
      ]
    }

    resource_fixture!(workspace, :suite, "my_suite", suite)

    resource_fixture!(workspace, :template, "my_template", %{
      "clients" => ["http"],
      "payload" => %{"a" => 1}
    })

    resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

    assert {:ok,
            %{
              testcases: [
                %{
                  name: "testcase 1",
                  steps: [
                    %{
                      client: "http",
                      dataset: %{data: %{"foo" => "bar"}},
                      template: %{clients: ["http"], payload: %{"a" => 1}, options: %{}}
                    }
                  ]
                }
              ]
            }} = Resolver.resolve(workspace, "my_suite")
  end

  describe "assertion atomization" do
    test "a template-step's assert entries atomize matcher/path/expected, expected stays as given",
         %{workspace: workspace} do
      suite = %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [
              %{
                "client" => "http",
                "template" => "my_template",
                "dataset" => "my_dataset",
                "assert" => [
                  %{"matcher" => "json_match", "path" => "$.total", "expected" => 42}
                ]
              }
            ]
          }
        ]
      }

      resource_fixture!(workspace, :suite, "my_suite", suite)

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

      assert {:ok,
              %{
                testcases: [
                  %{
                    steps: [
                      %{
                        assert: [%{matcher: "json_match", path: "$.total", expected: 42}]
                      }
                    ]
                  }
                ]
              }} = Resolver.resolve(workspace, "my_suite")
    end

    test "an assert entry without a matcher defaults to json_match", %{workspace: workspace} do
      suite = %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [
              %{
                "client" => "http",
                "template" => "my_template",
                "dataset" => "my_dataset",
                "assert" => [%{"expected" => 42}]
              }
            ]
          }
        ]
      }

      resource_fixture!(workspace, :suite, "my_suite", suite)

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

      assert {:ok,
              %{
                testcases: [
                  %{steps: [%{assert: [%{matcher: "json_match", expected: 42}]}]}
                ]
              }} = Resolver.resolve(workspace, "my_suite")
    end

    test "matcher-specific extra fields beyond matcher/path/expected stay string-keyed", %{
      workspace: workspace
    } do
      suite = %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [
              %{
                "client" => "http",
                "template" => "my_template",
                "dataset" => "my_dataset",
                "assert" => [
                  %{"matcher" => "db", "expected" => %{"exists" => true}, "table" => "orders"}
                ]
              }
            ]
          }
        ]
      }

      resource_fixture!(workspace, :suite, "my_suite", suite)

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

      assert {:ok, %{testcases: [%{steps: [%{assert: [assertion]}]}]}} =
               Resolver.resolve(workspace, "my_suite")

      assert assertion == %{
               :matcher => "db",
               :expected => %{"exists" => true},
               "table" => "orders"
             }
    end

    test "a scenario-call step rejects an assert field of its own only its nested steps can have one",
         %{workspace: workspace} do
      suite = %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [
              %{
                "scenario" => "my_scenario",
                "dataset" => "my_dataset",
                "assert" => [%{"expected" => 42}]
              }
            ]
          }
        ]
      }

      raw_resource_fixture!(workspace, :suite, "my_suite", suite)

      resource_fixture!(workspace, :scenario, "my_scenario", %{
        "steps" => [%{"client" => "http", "template" => "my_template"}]
      })

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

      assert {:error, {:invalid, _reasons}} = Resolver.resolve(workspace, "my_suite")
    end
  end

  test "resolve suite reference with scenario", %{workspace: workspace} do
    suite = %{
      "id" => "my-suite",
      "testcases" => [
        %{
          "id" => "testcase-1",
          "name" => "testcase 1",
          "steps" => [
            %{
              "scenario" => "my_scenario",
              "dataset" => "my_dataset"
            }
          ]
        }
      ]
    }

    resource_fixture!(workspace, :suite, "my_suite", suite)

    scenario = %{
      "steps" => [
        %{
          "client" => "http",
          "template" => "my_template"
        }
      ]
    }

    resource_fixture!(workspace, :scenario, "my_scenario", scenario)

    resource_fixture!(workspace, :template, "my_template", %{
      "clients" => ["http"],
      "payload" => %{"a" => 1}
    })

    resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

    assert {:ok,
            %{
              testcases: [
                %{
                  name: "testcase 1",
                  steps: [
                    %{
                      dataset: %{data: %{"foo" => "bar"}},
                      scenario: %{
                        default_dataset: %{data: %{"foo" => "bar"}},
                        steps: [
                          %{
                            client: "http",
                            dataset: %{data: %{"foo" => "bar"}},
                            template: %{
                              clients: ["http"],
                              payload: %{"a" => 1},
                              options: %{}
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
              ]
            }} = Resolver.resolve(workspace, "my_suite")
  end

  test "broadcasts default_dataset's data over the caller's rows, caller's fields winning", %{
    workspace: workspace
  } do
    suite = %{
      "id" => "my-suite",
      "testcases" => [
        %{
          "id" => "testcase-1",
          "name" => "testcase 1",
          "steps" => [
            %{"scenario" => "my_scenario", "dataset" => "seeded_users"}
          ]
        }
      ]
    }

    resource_fixture!(workspace, :suite, "my_suite", suite)

    resource_fixture!(workspace, :scenario, "my_scenario", %{
      "default_dataset" => %{"data" => %{"password" => "default-pw"}},
      "steps" => [%{"client" => "http", "template" => "my_template"}]
    })

    resource_fixture!(workspace, :template, "my_template", %{
      "clients" => ["http"],
      "payload" => %{"a" => 1}
    })

    resource_fixture!(workspace, :dataset, "seeded_users", %{
      "rows" => [
        %{"username" => "alice"},
        %{"username" => "bob", "password" => "bobs-own-pw"}
      ]
    })

    assert {:ok,
            %{
              testcases: [
                %{
                  steps: [
                    %{
                      dataset: %{
                        rows: [
                          %{"username" => "alice", "password" => "default-pw"},
                          %{"username" => "bob", "password" => "bobs-own-pw"}
                        ]
                      }
                    }
                  ]
                }
              ]
            }} = Resolver.resolve(workspace, "my_suite")
  end

  test "rejects a scenario call where both default_dataset and the caller's dataset have rows", %{
    workspace: workspace
  } do
    suite = %{
      "id" => "my-suite",
      "testcases" => [
        %{
          "id" => "testcase-1",
          "name" => "testcase 1",
          "steps" => [
            %{"scenario" => "my_scenario", "dataset" => "caller_rows"}
          ]
        }
      ]
    }

    resource_fixture!(workspace, :suite, "my_suite", suite)

    resource_fixture!(workspace, :scenario, "my_scenario", %{
      "default_dataset" => %{"rows" => [%{"username" => "alice"}]},
      "steps" => [%{"client" => "http", "template" => "my_template"}]
    })

    resource_fixture!(workspace, :template, "my_template", %{
      "clients" => ["http"],
      "payload" => %{"a" => 1}
    })

    resource_fixture!(workspace, :dataset, "caller_rows", %{"rows" => [%{"username" => "bob"}]})

    assert {:error, %{reason: :ambiguous_dataset_merge, path: [_ | _]}} =
             Resolver.resolve(workspace, "my_suite")
  end

  test "errors when a scenario call has no dataset, no inherited dataset, and no default_dataset",
       %{workspace: workspace} do
    suite = %{
      "id" => "my-suite",
      "testcases" => [
        %{
          "id" => "testcase-1",
          "name" => "testcase 1",
          "steps" => [%{"scenario" => "my_scenario"}]
        }
      ]
    }

    resource_fixture!(workspace, :suite, "my_suite", suite)

    resource_fixture!(workspace, :scenario, "my_scenario", %{
      "steps" => [%{"client" => "http", "template" => "my_template"}]
    })

    resource_fixture!(workspace, :template, "my_template", %{
      "clients" => ["http"],
      "payload" => %{"a" => 1}
    })

    assert {:error, %{reason: :no_dataset, path: [_ | _]}} =
             Resolver.resolve(workspace, "my_suite")
  end

  describe "fold_datasets/1" do
    test "a present dataset fills in when earlier entries are all nil" do
      caller = %{"data" => %{"username" => "alice"}}
      assert Resolver.fold_datasets([nil, nil, caller]) == {:ok, caller}
    end

    test "every entry nil is an error" do
      assert Resolver.fold_datasets([nil, nil, nil]) == {:error, :no_dataset}
    end

    test "later entries win on field collision" do
      assert Resolver.fold_datasets([
               %{"data" => %{"a" => 1, "b" => 1}},
               nil,
               %{"data" => %{"b" => 2}}
             ]) == {:ok, %{"data" => %{"a" => 1, "b" => 2}}}
    end
  end

  describe "merge_dataset/2" do
    test "data merges into data, next's fields winning" do
      assert Resolver.merge_dataset(%{"data" => %{"a" => 1}}, %{"data" => %{"a" => 2, "b" => 2}}) ==
               {:ok, %{"data" => %{"a" => 2, "b" => 2}}}
    end

    test "rows broadcast previous's data, row's own fields winning" do
      previous = %{"data" => %{"password" => "default-pw"}}
      next = %{"rows" => [%{"username" => "alice"}, %{"username" => "bob", "password" => "own"}]}

      assert Resolver.merge_dataset(previous, next) ==
               {:ok,
                %{
                  "rows" => [
                    %{"username" => "alice", "password" => "default-pw"},
                    %{"username" => "bob", "password" => "own"}
                  ]
                }}
    end

    test "data broadcasts into a previous rows table, row's own fields winning" do
      previous = %{
        "rows" => [%{"username" => "alice"}, %{"username" => "bob", "password" => "own"}]
      }

      next = %{"data" => %{"password" => "default-pw"}}

      assert Resolver.merge_dataset(previous, next) ==
               {:ok,
                %{
                  "rows" => [
                    %{"username" => "alice", "password" => "default-pw"},
                    %{"username" => "bob", "password" => "own"}
                  ]
                }}
    end

    test "both sides rows is rejected" do
      assert Resolver.merge_dataset(%{"rows" => [%{"a" => 1}]}, %{"rows" => [%{"b" => 2}]}) ==
               {:error, :ambiguous_dataset_merge}
    end

    test "nil on either side passes the other through unchanged" do
      present = %{"data" => %{"a" => 1}}
      assert Resolver.merge_dataset(present, nil) == {:ok, present}
      assert Resolver.merge_dataset(nil, present) == {:ok, present}
      assert Resolver.merge_dataset(nil, nil) == {:ok, nil}
    end
  end

  describe "scenario recursion guards" do
    test "rejects a scenario that calls itself", %{workspace: workspace} do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [%{"scenario" => "self_referential", "dataset" => "my_dataset"}]
          }
        ]
      })

      resource_fixture!(workspace, :scenario, "self_referential", %{
        "steps" => [%{"scenario" => "self_referential"}]
      })

      resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

      assert {:error, %{path: path, reason: reason}} = Resolver.resolve(workspace, "my_suite")

      assert reason ==
               {:cycle_detected, "self_referential", ["self_referential", "self_referential"]}

      assert List.last(path) == %{ref_kind: :scenario, ref_name: "self_referential"}
    end

    test "rejects an indirect cycle across two scenarios", %{workspace: workspace} do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [%{"scenario" => "scenario_a", "dataset" => "my_dataset"}]
          }
        ]
      })

      resource_fixture!(workspace, :scenario, "scenario_a", %{
        "steps" => [%{"scenario" => "scenario_b"}]
      })

      resource_fixture!(workspace, :scenario, "scenario_b", %{
        "steps" => [%{"scenario" => "scenario_a"}]
      })

      resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

      assert {:error, %{path: path, reason: reason}} = Resolver.resolve(workspace, "my_suite")
      assert reason == {:cycle_detected, "scenario_a", ["scenario_a", "scenario_b", "scenario_a"]}
      assert List.last(path) == %{ref_kind: :scenario, ref_name: "scenario_a"}
    end

    test "a deep but acyclic scenario chain hits the max depth guard", %{workspace: workspace} do
      chain_length = Resolver.max_scenario_depth() + 1

      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [%{"scenario" => "scenario_0", "dataset" => "my_dataset"}]
          }
        ]
      })

      resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

      for n <- 0..(chain_length - 1) do
        next_step =
          if n == chain_length - 1 do
            %{"client" => "http", "template" => "my_template"}
          else
            %{"scenario" => "scenario_#{n + 1}"}
          end

        resource_fixture!(workspace, :scenario, "scenario_#{n}", %{"steps" => [next_step]})
      end

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      max_depth = Resolver.max_scenario_depth()

      assert {:error, %{path: path, reason: {:max_depth_exceeded, ^max_depth}}} =
               Resolver.resolve(workspace, "my_suite")

      assert List.last(path) == %{ref_kind: :scenario, ref_name: "scenario_#{max_depth}"}
    end

    test "a scenario chain within the depth limit resolves normally", %{workspace: workspace} do
      chain_length = 10

      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [%{"scenario" => "scenario_0", "dataset" => "my_dataset"}]
          }
        ]
      })

      resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

      for n <- 0..(chain_length - 1) do
        next_step =
          if n == chain_length - 1 do
            %{"client" => "http", "template" => "my_template"}
          else
            %{"scenario" => "scenario_#{n + 1}"}
          end

        resource_fixture!(workspace, :scenario, "scenario_#{n}", %{"steps" => [next_step]})
      end

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      assert {:ok, _resolved} = Resolver.resolve(workspace, "my_suite")
    end
  end

  describe "error path pinpointing" do
    test "a missing template reference names the testcase, step, and template", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "add-to-cart",
            "name" => "Add to cart",
            "steps" => [
              %{
                "name" => "POST /cart",
                "client" => "http",
                "template" => "does_not_exist",
                "dataset" => %{"data" => %{"a" => 1}}
              }
            ]
          }
        ]
      })

      assert {:error, %{path: path, reason: :not_found}} = Resolver.resolve(workspace, "my_suite")

      assert path == [
               %{testcase_index: 0, testcase_name: "Add to cart"},
               %{step_index: 0, step_name: "POST /cart"},
               %{ref_kind: :template, ref_name: "does_not_exist"}
             ]
    end

    test "a missing dataset reference inside a scenario call names the whole chain", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [%{"scenario" => "my_scenario", "dataset" => "does_not_exist"}]
          }
        ]
      })

      resource_fixture!(workspace, :scenario, "my_scenario", %{
        "steps" => [%{"client" => "http", "template" => "my_template"}]
      })

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      assert {:error, %{path: path, reason: :not_found}} = Resolver.resolve(workspace, "my_suite")

      assert path == [
               %{testcase_index: 0, testcase_name: "testcase 1"},
               %{step_index: 0, step_name: nil},
               %{ref_kind: :dataset, ref_name: "does_not_exist"}
             ]
    end

    test "a schema-invalid dataset file surfaces {:invalid, reasons} at the right path", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [
              %{"client" => "http", "template" => "my_template", "dataset" => "broken_dataset"}
            ]
          }
        ]
      })

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      raw_resource_fixture!(workspace, :dataset, "broken_dataset", %{})

      assert {:error, %{path: path, reason: {:invalid, reasons}}} =
               Resolver.resolve(workspace, "my_suite")

      assert is_list(reasons)

      assert path == [
               %{testcase_index: 0, testcase_name: "testcase 1"},
               %{step_index: 0, step_name: nil},
               %{ref_kind: :dataset, ref_name: "broken_dataset"}
             ]
    end
  end

  describe "inline template and scenario" do
    test "an inline template needs no file at all", %{workspace: workspace} do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [
              %{
                "client" => "http",
                "template" => %{"clients" => ["http"], "payload" => %{"foo" => "{{foo}}"}},
                "dataset" => %{"data" => %{"foo" => "bar"}}
              }
            ]
          }
        ]
      })

      assert {:ok,
              %{
                testcases: [
                  %{
                    steps: [
                      %{
                        template: %{
                          clients: ["http"],
                          payload: %{"foo" => "{{foo}}"},
                          options: %{}
                        },
                        dataset: %{data: %{"foo" => "bar"}}
                      }
                    ]
                  }
                ]
              }} = Resolver.resolve(workspace, "my_suite")
    end

    test "an inline scenario needs no file at all, and its inline nested template resolves too",
         %{workspace: workspace} do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [
              %{
                "scenario" => %{
                  "default_dataset" => %{"data" => %{"password" => "default-pw"}},
                  "steps" => [
                    %{
                      "client" => "http",
                      "template" => %{"clients" => ["http"], "payload" => %{"a" => 1}}
                    }
                  ]
                },
                "dataset" => %{"data" => %{"username" => "alice"}}
              }
            ]
          }
        ]
      })

      assert {:ok,
              %{
                testcases: [
                  %{
                    steps: [
                      %{
                        scenario: %{
                          default_dataset: %{
                            data: %{"username" => "alice", "password" => "default-pw"}
                          },
                          steps: [
                            %{
                              template: %{clients: ["http"], payload: %{"a" => 1}, options: %{}},
                              dataset: %{
                                data: %{"username" => "alice", "password" => "default-pw"}
                              }
                            }
                          ]
                        }
                      }
                    ]
                  }
                ]
              }} = Resolver.resolve(workspace, "my_suite")
    end

    test "a named scenario calling an inline scenario still resolves, with no false cycle", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [%{"scenario" => "outer", "dataset" => "my_dataset"}]
          }
        ]
      })

      resource_fixture!(workspace, :scenario, "outer", %{
        "steps" => [
          %{
            "scenario" => %{
              "steps" => [%{"client" => "http", "template" => "my_template"}]
            }
          }
        ]
      })

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      resource_fixture!(workspace, :dataset, "my_dataset", %{"data" => %{"foo" => "bar"}})

      assert {:ok, _resolved} = Resolver.resolve(workspace, "my_suite")
    end

    test "an inline scenario referencing a missing named template still pinpoints the path", %{
      workspace: workspace
    } do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [
              %{
                "scenario" => %{
                  "steps" => [%{"client" => "http", "template" => "does_not_exist"}]
                },
                "dataset" => %{"data" => %{"a" => 1}}
              }
            ]
          }
        ]
      })

      assert {:error, %{path: path, reason: :not_found}} = Resolver.resolve(workspace, "my_suite")

      assert path == [
               %{testcase_index: 0, testcase_name: "testcase 1"},
               %{step_index: 0, step_name: nil},
               %{step_index: 0, step_name: nil},
               %{ref_kind: :template, ref_name: "does_not_exist"}
             ]
    end

    test "deeply nested inline scenarios still hit the max depth guard", %{workspace: workspace} do
      chain_length = Resolver.max_scenario_depth() + 1

      inline_chain =
        Enum.reduce(
          (chain_length - 1)..0//-1,
          %{"client" => "http", "template" => "my_template"},
          fn _n, inner ->
            %{"scenario" => %{"steps" => [inner]}}
          end
        )

      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "testcase-1",
            "name" => "testcase 1",
            "steps" => [Map.put(inline_chain, "dataset", %{"data" => %{"a" => 1}})]
          }
        ]
      })

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      assert {:error, %{reason: {:max_depth_exceeded, _max_depth}}} =
               Resolver.resolve(workspace, "my_suite")
    end
  end

  describe "testcase id uniqueness" do
    test "rejects a suite with duplicate testcase ids", %{workspace: workspace} do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "dup",
            "name" => "testcase 1",
            "steps" => [
              %{
                "client" => "http",
                "template" => "my_template",
                "dataset" => %{"data" => %{"a" => 1}}
              }
            ]
          },
          %{
            "id" => "dup",
            "name" => "testcase 2",
            "steps" => [
              %{
                "client" => "http",
                "template" => "my_template",
                "dataset" => %{"data" => %{"a" => 2}}
              }
            ]
          }
        ]
      })

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      assert Resolver.resolve(workspace, "my_suite") ==
               {:error, {:duplicate_testcase_id, "dup", [0, 1]}}
    end

    test "accepts a suite where every testcase has a distinct id", %{workspace: workspace} do
      resource_fixture!(workspace, :suite, "my_suite", %{
        "id" => "my-suite",
        "testcases" => [
          %{
            "id" => "first",
            "name" => "testcase 1",
            "steps" => [
              %{
                "client" => "http",
                "template" => "my_template",
                "dataset" => %{"data" => %{"a" => 1}}
              }
            ]
          },
          %{
            "id" => "second",
            "name" => "testcase 2",
            "steps" => [
              %{
                "client" => "http",
                "template" => "my_template",
                "dataset" => %{"data" => %{"a" => 2}}
              }
            ]
          }
        ]
      })

      resource_fixture!(workspace, :template, "my_template", %{
        "clients" => ["http"],
        "payload" => %{"a" => 1}
      })

      assert {:ok, _resolved} = Resolver.resolve(workspace, "my_suite")
    end
  end
end
