const bcrypt = require('bcryptjs');
const hash = '$2b$10$7vj2G4bUvIymX78w58eJp.v7P2X4Y8k21eZ3O.2w8.cEq8n1y8Wc6';
bcrypt.compare('123456', hash).then(res => {
    console.log('Password "123456" matches hash:', res);
}).catch(err => {
    console.error(err);
});
