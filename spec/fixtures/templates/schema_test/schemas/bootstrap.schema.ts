import { z } from 'zod';

const schema = z.object({
  appName: z.string(),
  version: z.string(),
  features: z.array(z.string()).optional()
});

export default schema;
