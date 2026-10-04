import socket
import sys
import random
from time import sleep
import des
import library

#for the purpose of this assignment, both clients know these
HOST = "127.0.0.1"
PORT = 5010

KDC_key = None
MyId = None

#method for printing the options for the client
def printMenuOptions():
    print("Options:")
    print("\t Enter 'quit' to exit")
    print("\t Enter 'list' to list established secure users")
    print("\t Enter 'connect|id to connect to id")

# method that creates a random 10 bit key
def random10bit():
	num = ""
	for i in range(10):
		rand = random.randint(0,1)
		num += str(rand)
	return int(num,2)

#method that creates a random 10 bit number as a string to serve as our nonce
def nonceGenerator():
    return format(random.randint(1, 1023), "010b")

#method that performs the NS protocol
def needhamSchroeder(soc):
    #receiving the package from step 2
    message = library.receiveMessage(soc)
    if not message:
        raise ConnectionError("KDC closed the connection before replying")

    #decrypting the message
    decrypedMessage = library.decrypt(message,KDC_key)
    Ks = decrypedMessage[0:10]
    IDb = decrypedMessage[10:18]
    T = decrypedMessage[18:28]
    smallEncryption = decrypedMessage[28:]
    print("Received the KDC response and Bob's encrypted ticket")
    #now we connect to the harcoded channel client 2 is waiting for us to connect to
    with socket.socket() as mySocket:
        mySocket.connect((HOST,PORT))
        #sending over step 3 to Bob
        print("Forwarding Bob's ticket")
        library.sendMessage(mySocket, smallEncryption)
        #receiving step 4 from Bob
        newNonce = library.receiveMessage(mySocket)
        if not newNonce:
            raise ConnectionError("Bob closed the connection during authentication")
        #decrypting step 4
        decryptedNonce = library.decrypt(newNonce,Ks)
        #turning it into and int
        changedNonce = int(decryptedNonce,2) - 1
        #turning it back into a binary string
        changedNonce = bin(changedNonce)[2:].zfill(10)
        #encrypting f(nonce)
        encryptedNonce = library.encrypt(changedNonce, Ks)
        #sending step 5 to Bob
        library.sendMessage(mySocket, encryptedNonce)
        
        #if Bob received the anticipated differentiation in nonce value
        #using the same encryption/decryption key..... 
        #We now have a secure chat!
        if library.receiveMessage(mySocket) != "VERIFIED":
            raise ConnectionError("Bob did not verify the session key")
        print("Bob verified the nonce challenge; secure chat established")
        while message != 'q':

            message = input("Enter the message you want to encrypt -> ")
            #encrypting the message using DES
            finalEncryptedMessage = library.encrypt(message,Ks)

            library.sendMessage(mySocket, finalEncryptedMessage)
            if message == 'q':
                break
            #receiving the response from the other user
            data = library.receiveMessage(mySocket)
            if not data:
                break
            #decrypting the other user's message
            decryptedMessage = library.decrypt(data,Ks)
            print ("Decrypted Message = " + str(decryptedMessage))

#method that runs that diffie helman exchange for the client
def diffieHelman(kdc, PrivateKey):
    # message = kdc.recv(1024).decode('utf8')
    
    #note b is the private key
    #receive public G and P from server
    message = library.receiveMessage(kdc)
    message = message.split("|")
    # print(message)
    publicP, publicG = int(message[1]),int(message[2])
    global MyId
    MyId = message[0]


    #receives the first calculation
    #call this X
    A = int(library.receiveMessage(kdc))

    #generate 10 bit key for KDC
    #call this a
    #now it's time for the client to do their step
    #B = g^b mod p
    b = random10bit()
    B = (publicG**b)%publicP

    #now we send this to the server
    library.sendMessage(kdc, str(B))

    #now we do the final calculation
    #S = A^b mod p
    S = (A**b)%publicP
    global KDC_key
    KDC_key = bin(S)[2:].zfill(10)
    print("Established key = ", str(S))


def main():
    soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    host = "127.0.0.1"
    port = 5000

    try:
        soc.connect((host, port))
    except:
        print("Connection error")
        sys.exit()

    #create the key and use it in function call
    Key = random10bit()
    diffieHelman(soc,Key)


    while True:
        #print the user options
        printMenuOptions()
        message = input(" -> ").strip()

        if message == "quit":
            library.sendMessage(soc, message)
            break

        if message == "list":
            library.sendMessage(soc, message)
            userList = library.receiveMessage(soc)
            print(userList)
            continue

        if message.startswith("connect|"):
            print("trying to connect")
            otherUser = message.split("|", 1)[1]
            if len(otherUser) != 8 or not otherUser.isdigit():
                print("Enter a valid 8-digit user ID, for example connect|00000001")
                continue
            #this is for the server-side backend
            message = 'connect|' + MyId + otherUser + nonceGenerator()
            library.sendMessage(soc, message)
            #go up to the NS method and start the interaction
            needhamSchroeder(soc)
            continue

        print("Unknown command. Enter 'list', 'connect|id', or 'quit'.")

    soc.close()

if __name__ == "__main__":
    main()