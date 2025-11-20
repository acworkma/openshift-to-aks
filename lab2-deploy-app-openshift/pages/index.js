export async function getServerSideProps() {
  return {
    props: {
      message: process.env.APP_MESSAGE || 'Hello from Next.js on OpenShift',
      environment: process.env.APP_ENVIRONMENT || 'dev'
    }
  };
}

export default function Home({ message, environment }) {
  return (
    <main style={{ fontFamily: 'system-ui', padding: '2rem' }}>
      <h1>{message}</h1>
      <p>Environment: {environment}</p>
      <p>Health endpoint: <code>/api/health</code></p>
    </main>
  );
}
