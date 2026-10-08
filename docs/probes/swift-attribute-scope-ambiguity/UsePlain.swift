import Scope
var a = AttributedString("x")
a.foregroundColor = .red
let c: MColor? = a.foregroundColor
print("ok", c as Any)
