import Foundation

print("AwakeController")

let controller = AwakeController()

check(!controller.isOn, "starts off")
check(!processHoldsDisplayAssertion(), "holds no assertion before enable()")

controller.enable()
check(controller.isOn, "isOn is true after enable()")
check(processHoldsDisplayAssertion(), "kernel reports our assertion after enable()")

controller.enable()
check(controller.isOn, "redundant enable() keeps it on")
check(processHoldsDisplayAssertion(), "redundant enable() does not lose the assertion")

controller.disable()
check(!controller.isOn, "isOn is false after disable()")
check(!processHoldsDisplayAssertion(), "kernel released the assertion after disable()")

controller.disable()
check(!controller.isOn, "redundant disable() is a no-op")

controller.toggle()
check(controller.isOn, "toggle() from off turns on")
check(processHoldsDisplayAssertion(), "toggle() on takes the assertion")

controller.toggle()
check(!controller.isOn, "toggle() from on turns off")
check(!processHoldsDisplayAssertion(), "toggle() off releases the assertion")

if failureCount > 0 {
    print("\n\(failureCount) failure(s)")
    exit(1)
}
print("\nall tests passed")
