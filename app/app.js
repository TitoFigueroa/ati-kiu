const express = require('express');
const bodyParser = require('body-parser');
const mysql2 = require('mysql2');

const app = express();
const port = 3000;

app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());

// MySQL connection setup with mysql2
const connection = mysql2.createConnection({
  host: 'mysql',
  port: '3306',
  user: 'app_user',
  password: 'app_password',
  database: 'mydatabase',
  insecureAuth: true // Using an older authentication method for testing purposes
});

// Validate database connection before starting the app
connection.connect((err) => {
  if (err) {
    console.error('Error connecting to database:', err.message);
    process.exit(1);
  }
  console.log('Connected to the database');

  // Express route for the root path
  app.get('/', (req, res) => {
    // Render a basic HTML form
    res.send(`
      <html>
        <body>
          <h1>Node.js App</h1>
          <form action="/submit" method="post">
            <label for="name">Enter your name:</label>
            <input type="text" id="name" name="text" required>
            <button type="submit">Save</button>
          </form>
        </body>
      </html>
    `);
  });

  // Express route to handle POST requests
  app.post('/submit', (req, res) => {
    const userInput = req.body.text;

    if (/^[a-zA-Z\s]+$/.test(userInput)) {
      const query = 'INSERT INTO app_data (input_text) VALUES (?)';

      console.log('Executing query:', query, 'with input:', userInput);

      connection.query(query, [userInput], (error, results) => {
        if (error) {
          console.error('Error executing query:', error);
          res.status(500).send('Error storing data');
        } else {
          console.log('Query executed successfully. Rows affected:', results.affectedRows);
          console.log('Data stored successfully');
          res.send('Data stored successfully');
        }
      });
    } else {
      console.error('Invalid input format:', userInput);
      res.status(400).send('Invalid input format');
    }
  });

  app.listen(port, () => {
    console.log(`App listening at http://localhost:${port}`);
  });
});

// Handle database connection errors during app runtime
connection.on('error', (err) => {
  console.error('Database connection error:', err.message);
  process.exit(1);
});
