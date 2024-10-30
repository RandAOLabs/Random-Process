-- calculator_spec.lua
local calculator = require("calculator")

describe("Calculator", function()
    it("adds two numbers", function()
        assert.are.equal(5, calculator.add(2, 3))
    end)

    it("subtracts two numbers", function()
        assert.are.equal(1, calculator.subtract(3, 2))
    end)
end)
