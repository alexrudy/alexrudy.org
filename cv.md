---
layout: page
title: Resume
permalink: /cv/
---
<style>
li {
    font-size: 0.8em;
}
.post-content h1 {
    font-size: 1.6em;
}
.post-content h2 {
    font-size: 1.2em;
}
p {
    font-size: 0.9em;
}
</style>

Find me elsewhere online at [LinkedIn][], [Github][], or [Twitter][].

[LinkedIn]: https://www.linkedin.com/in/alexrudy/
[Github]: https://github.com/alexrudy
[Twitter]: https://twitter.com/alexrudy

# Overview
- Strategy and execution focused, seeking small teams where I can have a big impact and fill gaps across an organization.
- Experience which spans model building, backend engineering, data warehouses, and machine learning pipelines.
- Strong track record of deploying high-impact compliant machine learning models for a variety of business applications.
- Experience with a wide variety of modeling techniques: tree-based ensemble models, neural networks, hierarchical bayesian models, regression, and ruin-and-recreate optimization problems.
- Proven system architect: high-throughput backend APIs, data warehouses, ELT pipelines, and ML pipelines.
- Developed and deployed extensively in Python, SQL, C and Rust. Experience with C++, Go, JavaScript, Ruby, Fortran & R. Maintained CI pipelines, canonical docker images, and contributes to open source python (papermill & matplotlib).

# Experience

## Staff Machine Learning Engineer, Platform
**[Discord](https://discord.com) -- San Francisco, CA** - *August 2022 to Present*

Building belonging and enabling effective data science and machine learning teams for Discord.

## Principal Machine Learning Engineer
**[CloudTrucks](https://www.cloudtrucks.com) -- San Francisco, CA** -- *March 2021 to June 2022*

- Architect for a partner load board query caching and crawling system, solving pain points with our existing Django on-demand load search, API, and RPA system. Re-designed the core truck load data models used at CloudTrucks to power our entire app, and built a system designed to scale integrations and search queries.
- Built and deployed a route optimization tool backed by an adaptive ruin and recreate algorithm which powers the Schedule Optimizer, a tentpole feature for CloudTrucks, driving signups for our Flex and Virtual Carrier products. Built new algorithms and compatible API in Rust, leveraging h3, PyO3, tokio, and serde to provide backwards compatible interfaces to existing python code.
- Responsible for Docker, Python, Django and CircleCI infrastructure, including Celery task queues, dependency management, testing infrastructure, and continuous deployment of our container images. Partner with our primary infrastructure engineer to maintain our Google Cloud Platform infrastructure, networking, proxying, host management, metrics, and monitoring – using terraform, prometheus and grafana.
- Technical mentor, leader and educator – responsible for building the CloudTrucks technical onboarding program, teaching intermediate and advanced python skills, writing the company Python and Django style guide, and ensuring that CloudTrucks has a high quality developer experience from day one, leveraging tools like homebrew, pre-commit, mypy type checking and docker-compose to help maintain a uniform environment and high quality code base.
- Maintain a complex regulatory and compliance framework for identifying likely drive-time violations in the future, which helps to power our in-house compliance and operational monitoring tools, as well as providing a key component to the schedule optimizer.## Head of Data Science


## Principal Data Scientist
**[Bitly](https://bitly.com) IQ -- San Francisco, CA** -- *August 2019 to March 2021*

- Created a family of natural language skip-gram models for semantic tagging of the billions of crawled pages observed in links on the Bitly platform, specialized to individual consumer product verticals, and leveraged these models to predict rising and falling demand trends in a way which was robust to the disruptions from the initial wave of COVID.
- Built a cloud-native machine learning pipeline for building models using TensorFlow on Bitly’s click and web history, taking data from BigQuery and google cloud storage, pre-processing with data flow pipelines, training on Google’s TPU infrastructure, and deployed using docker containers on Google Kubernetes Engine, all orchestrated using GCP’s AirFlow equivalent Cloud Composer.
- Developed a BERT-descendant natural language model to identify suspicious and malicious URLs on the Bitly platform.

## Senior Data Scientist
**[Even](https://even.com) -- Oakland, CA – Founding member of the data team** -- *March 2018 to August 2019*

- Developed a novel ML algorithm to apply active learning and hierarchical clustering to personal financial transaction data. The algorithm allows our app to budget for predictable expenses, powering 250,000 personal financial plans.
- Led the design and architecture of a new data warehouse to expose business data to Even employees. Built and evangelized the use of transformed data with business definitions, democratizing analysis across the company.
- Wrote and developed an impact study demonstrating the 45% improvement to employee retention associated with using the Even app in collaboration with Walmart’s Human Resources and Benefits departments.
- Bootstrapped and launched an underwriting model to identify working hours of employees using location data.
- Mentor and technical leader for Data Scientists and Data Engineers on the data team.

## Data Scientist
**LendUp -- San Francisco, CA – became [Mission Lane](https://www.missionlane.com) in 2018** -- *July 2017 to March 2018*

- Built and deployed a performant, ECOA compliant underwriting model for applicants with bankruptcies which accounts for 80% of credit card approvals and drove significant business growth.
- Created a data-driven credit card net present value model for our portfolio and a business intelligence GUI which became the primary tool for data driven product strategy decisions.
- Developed a loss-rate forecasting model to allow early identification of credit card defaults in the first 3 statements.

## National Science Foundation Research Fellow
**[University of California, Santa Cruz](https://ucsc.edu), [University of California Observatories](https://ucolick.org), and [Lawrence Livermore National Laboratory](https://www.llnl.gov)** -- *September 2012 to July 2017*

- Developed operational and real time software for a research facility adaptive optics instrument at Lick Observatory.
- Demonstrated the use of a predictive Kalman filter to correct for wind errors on a 1kHz adaptive optics system.

## Fulbright Research Fellow
**[Foundation for Scholarly Exchange](http://www.fulbright.org.tw) and [National Central University Graduate Institute of Astronomy](http://www.astro.ncu.edu.tw/) – Zhongli, Taiwan** -- *September 2011 to June 2012*

# Education

**PhD, Astrophysics**, University of California Santa Cruz, CA -- July 2017
    <br />*Advisor: Claire Max. Thesis Topics: Predictive Control for Adaptive Optics, Gas Dynamics of Nearby Galaxies*

**BA, cum laude, Physics**, Pomona College, Claremont, CA -- May 2011
