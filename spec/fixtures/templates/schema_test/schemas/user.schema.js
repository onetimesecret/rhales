const { z } = require('zod');

const schema = z.object({
  id: z.number(),
  name: z.string(),
  email: z.string().email()
});

module.exports = schema;
