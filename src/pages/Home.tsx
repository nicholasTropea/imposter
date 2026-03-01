import styles from '../styles/Home.module.scss';

import { useNavigate } from 'react-router';

import Nav from '../components/Nav';

import { Flex, Button } from 'antd';
import {
    CrownOutlined,
    PlusOutlined,
    SearchOutlined
} from '@ant-design/icons'; 


const Home = () => {    
    const navigate = useNavigate();

    const goToCreateGame = () => {
        navigate('/create-game');
    }

    return (
        <Flex className = { styles.container } vertical>
            <Flex className = { styles.main } vertical>
                <Flex
                    className = { styles.info }
                    vertical
                    justify = 'center'
                    align = 'center'
                    gap = 'middle'
                >
                    <h1>Ready to spot the imposter?</h1>
                    <h3>One word is wrong. Some players are lying. Find them.</h3>
                </Flex>

                <Flex
                    className = { styles.actions }
                    vertical
                    justify = 'space-around'
                    align = 'space-around'
                >
                    <Button
                        type='primary'
                        icon = { <CrownOutlined /> }
                    >
                        Ranked Game
                    </Button>

                    <Flex justify = 'space-around' align = 'center'>
                        <Button
                            onClick = { goToCreateGame }
                            icon = { <PlusOutlined /> }
                        >
                            Create Game
                        </Button>

                        <Button icon = { <SearchOutlined /> }>Search Game</Button>
                    </Flex>
                </Flex>
            </Flex>

            <Nav />
        </Flex>
    );
}

export default Home;