import SwiftIO
import MadBoard

let pin = DigitalOut(Id.GREEN)
let uart = UART(Id.UART0)

while true {
    pin.toggle()
    //wait(us: 1000000) // accurate 1ms wait
    
    //uart.write("Hello SwiftIO!\n\0")
    print("Hello SwiftIO!")
    wait(us: 1000000) // accurate 1ms wait
}
