#!/bin/bash

###
# Initialize the database with test data
###

mongosh <<EOF
use somedb
for(var i = 0; i < 1200; i++) {
    db.users.insertOne({
        _id: i,
        name: "user_" + i,
        age: Math.floor(Math.random() * 100)
    })
}
EOF

